# File Archive Script

PowerShell file archiving utility that moves old files from configured source folders into archive folders.

The script is configured through `config.json` and supports:

- multiple source folders
- per-target overrides
- file age in seconds
- extension filtering
- archive path templates with `{year}` and `{month}`
- test mode
- size-based zipped log rotation
- scheduled execution through Windows FSRM

## Project Structure

Example project folder:

```text
C:\ArhivaTest
|-- Start-FileArchive.ps1
|-- config.json
|-- archive-lib
|   |-- Archive.Config.ps1
|   |-- Archive.Files.ps1
|   |-- Archive.Logging.ps1
|   |-- Archive.Run.ps1
|   `-- Archive.Settings.ps1
|-- Logs
`-- TestFiles
    |-- SourceA
    `-- SourceB
```

`TestFiles` is only a generic example folder for files used while testing this project. In production, use any folder names and paths that match your environment.

## Download And Setup

1. Open PowerShell.

2. Clone the project from Git into `C:\ArhivaTest`:

```powershell
git clone <repository-url> C:\ArhivaTest
```

Replace `<repository-url>` with the real Git repository URL.

3. Go into the project folder:

```powershell
cd C:\ArhivaTest
```

4. Create generic test folders:

```powershell
New-Item -ItemType Directory -Path "C:\ArhivaTest\TestFiles\SourceA" -Force
New-Item -ItemType Directory -Path "C:\ArhivaTest\TestFiles\SourceB" -Force
New-Item -ItemType Directory -Path "C:\ArhivaTest\Logs" -Force
```

5. Create or edit `config.json` in the project folder:

```powershell
notepad C:\ArhivaTest\config.json
```

Use the example `config.json` below as a starting point.

6. For a first test run, set `TestMode` to `true` in `config.json`. This logs what would happen without moving files.

7. Run the script:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-FileArchive.ps1"
```

8. Check the log output:

```text
C:\ArhivaTest\Logs\FileArchive.log
```

9. When the test output looks correct, set `TestMode` to `false` and run the same command again.

To update an existing local copy later:

```powershell
cd C:\ArhivaTest
git pull
```

## Run

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-FileArchive.ps1"
```

The script expects `config.json` to be in the same folder as `Start-FileArchive.ps1`.

## Scheduled Run With FSRM

You can use Windows File Server Resource Manager (FSRM) to run the archive script automatically, for example once per day.

Use this command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-FileArchive.ps1"
```

Typical setup:

1. Open **File Server Resource Manager**.
2. Go to **File Management Tasks**.
3. Create a new file management task.
4. Configure the task scope according to your environment. The script itself reads all source folders from `config.json`.
5. Configure the task action or command to run:

```text
Program/script:
powershell.exe

Arguments:
-ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-FileArchive.ps1"

Start in:
C:\ArhivaTest
```

6. Configure the schedule, for example **Daily**.
7. Run the task first with `TestMode: true` in `config.json`.
8. Check `C:\ArhivaTest\Logs\FileArchive.log`.
9. When the output is correct, set `TestMode` to `false`.

The FSRM task account must have read access to source folders and write access to archive folders and the `Logs` folder.

## Example `config.json`

```json
{
  "Defaults": {
    "MaxLogSizeMB": 20,
    "LogRotateCount": 5,
    "OlderThanSeconds": 2592000,
    "Extensions": [".txt", ".pdf", ".docx", ".bmp"],
    "ArchiveFolder": "Arhiva",
    "TestMode": false
  },
  "Targets": [
    {
      "Name": "SourceA",
      "Path": "C:\\ArhivaTest\\TestFiles\\SourceA",
      "ArchiveFolder": "C:\\ArhivaTest\\TestFiles\\SourceA\\{year}\\Example\\{month}",
      "OlderThanSeconds": 30,
      "Extensions": [".txt"],
      "Enabled": true
    },
    {
      "Name": "SourceB",
      "Path": "C:\\ArhivaTest\\TestFiles\\SourceB",
      "OlderThanSeconds": 30,
      "Extensions": [".pdf", ".docx", ".txt", ".bmp"],
      "Enabled": true
    }
  ]
}
```

## Configuration

`Defaults` contains values used by all targets unless a target overrides them.

`Targets` contains the source folders that should be archived.

| Field | Description |
| --- | --- |
| `MaxLogSizeMB` | Maximum size of the active log file before rotation. |
| `LogRotateCount` | Number of zipped rotated log files to keep. |
| `OlderThanSeconds` | Archive files older than this many seconds, based on `LastWriteTime`. |
| `Extensions` | File extensions that are allowed to be archived. |
| `ArchiveFolder` | Archive folder or archive path. Can include `{year}` and `{month}`. |
| `ArchivePath` | Optional explicit archive path. If set, it takes priority over `ArchiveFolder`. |
| `TestMode` | When `true`, logs what would happen without moving files. |
| `Enabled` | Enables or disables one target. |

## Archive Folder Templates

The archive path can contain these tokens:

- `{year}`: four-digit year from the file `LastWriteTime`, for example `2026`
- `{month}`: two-digit month from the file `LastWriteTime`, for example `08`

Examples:

```json
{
  "ArchiveFolder": "Arhiva"
}
```

If no date token is used, the script automatically groups by year:

```text
C:\ArhivaTest\TestFiles\SourceA\Arhiva\2026\file.txt
```

```json
{
  "ArchiveFolder": "Arhiva\\{year}"
}
```

```text
C:\ArhivaTest\TestFiles\SourceA\Arhiva\2026\file.txt
```

```json
{
  "ArchiveFolder": "Arhiva\\{year}\\{month}"
}
```

```text
C:\ArhivaTest\TestFiles\SourceA\Arhiva\2026\08\file.txt
```

```json
{
  "ArchiveFolder": "D:\\Archive\\SourceA\\{year}\\{month}"
}
```

```text
D:\Archive\SourceA\2026\08\file.txt
```

## Log Rotation

Logs are written to:

```text
Logs\FileArchive.log
```

When `FileArchive.log` grows beyond `MaxLogSizeMB`, it is compressed and rotated:

```text
FileArchive.log
FileArchive.log.1.zip
FileArchive.log.2.zip
FileArchive.log.3.zip
```

`LogRotateCount` controls how many rotated `.zip` logs are kept. When the count is exceeded, the oldest rotated log is deleted.

## Notes

- Files are moved, not copied.
- Existing files inside the archive folder are skipped during future archive runs.
- If a destination file already exists, the script appends a timestamp to avoid overwriting it.
- Use `TestMode: true` before running a new configuration in production.
