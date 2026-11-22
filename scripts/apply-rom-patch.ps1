param(
    [Parameter(Mandatory = $true)]
    [string]$Rom,
    [string]$Patch = "",
    [string]$Out = "",
    [string]$Root = ""
)
$ErrorActionPreference = "Stop"
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = Split-Path -Parent $scriptDirectory }
if (-not $Patch) { $Patch = Join-Path $Root "patches\rom\Shadowrun (USA) 1995 Four Classes.ips" }
if (-not $Out) { $Out = Join-Path $Root "game\shadowrun.bin" }

Add-Type -TypeDefinition @"
public static class ShadowrunCrc32
{
    private static readonly uint[] Table = BuildTable();
    private static uint[] BuildTable()
    {
        uint[] table = new uint[256];
        for (uint index = 0; index < 256; index++)
        {
            uint remainder = index;
            for (int bit = 0; bit < 8; bit++)
            {
                remainder = (remainder & 1) != 0 ? 0xEDB88320u ^ (remainder >> 1) : remainder >> 1;
            }
            table[index] = remainder;
        }
        return table;
    }
    public static uint Compute(byte[] data)
    {
        uint crc = 0xFFFFFFFFu;
        foreach (byte value in data)
        {
            crc = Table[(crc ^ value) & 0xFF] ^ (crc >> 8);
        }
        return ~crc;
    }
}
"@

$stockIdentity = [PSCustomObject]@{
    Crc32 = "FBB92909"
    Sha1  = "A06A281D39E845BFF446A541B2FF48E1D93143C2"
}
$patchedIdentity = [PSCustomObject]@{
    Crc32 = "93B0D845"
    Sha1  = "2F0FFB4C402972A183C936C17A10E9941123AC07"
}
$cartridgeSize = 2097152

function Get-ImageIdentity {
    param([byte[]]$ImageBytes)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        $digest = $sha1.ComputeHash($ImageBytes)
    } finally {
        $sha1.Dispose()
    }
    [PSCustomObject]@{
        Crc32 = ([ShadowrunCrc32]::Compute($ImageBytes)).ToString("X8")
        Sha1  = [BitConverter]::ToString($digest).Replace("-", "")
    }
}

function Test-ImageIdentity {
    param([PSCustomObject]$Identity, [PSCustomObject]$Expected)
    $Identity.Crc32 -eq $Expected.Crc32 -and $Identity.Sha1 -eq $Expected.Sha1
}

function Invoke-IpsPatch {
    param([byte[]]$RomBytes, [byte[]]$PatchBytes)
    if ($PatchBytes.Length -lt 8) { throw "patch is too short to be an IPS file" }
    if ([Text.Encoding]::ASCII.GetString($PatchBytes, 0, 5) -ne "PATCH") {
        throw "patch does not start with PATCH; IPS32 and BPS are not supported"
    }
    $imageBytes = [byte[]]$RomBytes.Clone()
    $cursor = 5
    while ($true) {
        if ($cursor + 3 -gt $PatchBytes.Length) { throw "patch ends before its EOF marker" }
        if ($PatchBytes[$cursor] -eq 0x45 -and
            $PatchBytes[$cursor + 1] -eq 0x4F -and
            $PatchBytes[$cursor + 2] -eq 0x46) {
            $cursor += 3
            break
        }
        $offset = ([int]$PatchBytes[$cursor] -shl 16) -bor ([int]$PatchBytes[$cursor + 1] -shl 8) -bor [int]$PatchBytes[$cursor + 2]
        $cursor += 3
        if ($cursor + 2 -gt $PatchBytes.Length) { throw "patch ends inside a record header" }
        $length = ([int]$PatchBytes[$cursor] -shl 8) -bor [int]$PatchBytes[$cursor + 1]
        $cursor += 2
        if ($length -eq 0) {
            if ($cursor + 3 -gt $PatchBytes.Length) { throw "patch ends inside an RLE record" }
            $runLength = ([int]$PatchBytes[$cursor] -shl 8) -bor [int]$PatchBytes[$cursor + 1]
            $fillByte = $PatchBytes[$cursor + 2]
            $cursor += 3
            if ($offset + $runLength -gt $imageBytes.Length) { throw "RLE record at 0x{0:X6} runs past the image" -f $offset }
            for ($index = 0; $index -lt $runLength; $index++) { $imageBytes[$offset + $index] = $fillByte }
        } else {
            if ($cursor + $length -gt $PatchBytes.Length) { throw "patch ends inside record data" }
            if ($offset + $length -gt $imageBytes.Length) { throw "record at 0x{0:X6} runs past the image" -f $offset }
            [Array]::Copy($PatchBytes, $cursor, $imageBytes, $offset, $length)
            $cursor += $length
        }
    }
    if ($cursor -ne $PatchBytes.Length) { throw "patch has $($PatchBytes.Length - $cursor) trailing bytes after EOF" }
    return , $imageBytes
}

$romPath = (Resolve-Path $Rom).Path
$patchPath = (Resolve-Path $Patch).Path
$outPath = [IO.Path]::GetFullPath($Out)
$romBytes = [IO.File]::ReadAllBytes($romPath)
if ($romBytes.Length -ne $cartridgeSize) {
    throw "$romPath is $($romBytes.Length) bytes; the USA dump is $cartridgeSize bytes. A header or a wrong region will not patch."
}
$romIdentity = Get-ImageIdentity $romBytes
$alreadyPatched = Test-ImageIdentity $romIdentity $patchedIdentity
if ($alreadyPatched) {
    Write-Host "input is already the four-class image - copying it" -ForegroundColor Yellow
    $imageBytes = $romBytes
} elseif (Test-ImageIdentity $romIdentity $stockIdentity) {
    $imageBytes = Invoke-IpsPatch $romBytes ([IO.File]::ReadAllBytes($patchPath))
} else {
    throw ("unknown cartridge image: CRC32 {0}, SHA-1 {1}. Expected the stock USA dump ({2}, {3})." -f `
        $romIdentity.Crc32, $romIdentity.Sha1, $stockIdentity.Crc32, $stockIdentity.Sha1)
}
$imageIdentity = Get-ImageIdentity $imageBytes
if (-not (Test-ImageIdentity $imageIdentity $patchedIdentity)) {
    throw ("patched image does not match the pin: CRC32 {0}, SHA-1 {1}. Expected {2}, {3}." -f `
        $imageIdentity.Crc32, $imageIdentity.Sha1, $patchedIdentity.Crc32, $patchedIdentity.Sha1)
}
$outDirectory = Split-Path -Parent $outPath
if (-not (Test-Path $outDirectory)) { New-Item -ItemType Directory -Path $outDirectory -Force | Out-Null }
[IO.File]::WriteAllBytes($outPath, $imageBytes)
if (-not $alreadyPatched) {
    Write-Host ("applied {0} to {1}" -f (Split-Path -Leaf $patchPath), (Split-Path -Leaf $romPath)) -ForegroundColor Green
}
Write-Host ("wrote {0}  size {1}  CRC32 {2}  SHA-1 {3}" -f $outPath, $imageBytes.Length, $imageIdentity.Crc32, $imageIdentity.Sha1)
