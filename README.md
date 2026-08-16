# File Archive Script

PowerShell file archiving utility that moves old files from configured source folders into archive folders.

The script is configured through `config.json` and supports:

- multiple source folders
- per-target overrides
- file age in seconds
- extension filtering
- archive date based on last modification time or creation time
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

## Portable Single-File Build

You can build one portable PowerShell file that contains the archive runner, config wizard, scheduled-task helper, and `archive-lib` runtime.

Build locally:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ".\build\Build-SingleFile.ps1" -Version "1.0.0"
```

Output:

```text
dist
|-- files-archive-1.0.0
|   |-- FileArchive.Portable.ps1
|   |-- README.md
|   `-- README.PORTABLE.txt
`-- files-archive-1.0.0.zip
```

Copy only `FileArchive.Portable.ps1` to a server if you want a single-file deployment.

Start the portable menu:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\FileArchive.Portable.ps1"
```

The menu provides these basic actions:

- run the archive script
- build or edit `config.json` through the wizard
- register or update the Windows Scheduled Task
- extract the normal multi-file runtime
- show active paths/status

Run archive directly from the portable file, for automation or Task Scheduler:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\FileArchive.Portable.ps1" -Mode Archive
```

Run the config wizard from the portable file:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\FileArchive.Portable.ps1" -Mode Wizard
```

Register or update the Windows Scheduled Task from the portable file:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\FileArchive.Portable.ps1" -Mode RegisterTask
```

Extract the normal multi-file runtime from the portable file:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\FileArchive.Portable.ps1" -Mode Extract -ExtractTo ".\runtime"
```

The portable script expects `config.json` and `scheduled-task.json` next to `FileArchive.Portable.ps1` unless you pass explicit paths with `-ConfigFile` or `-TaskConfigFile`.

Release builds are automated through GitHub Actions. Publishing a GitHub Release or pushing a `v*` tag builds the portable ZIP and `FileArchive.Portable.ps1`, then attaches both files directly to the GitHub Release assets for one-click download.

Typical release flow:

```bash
git tag v1.0.0
git push origin v1.0.0
```

After the workflow finishes, open the GitHub Release page and download either:

- `FileArchive.Portable.ps1` for single-file deployment
- `files-archive-<version>.zip` for the packaged release

## Config Wizard

Use the wizard to create or modify `config.json` without editing JSON manually:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-ConfigWizard.ps1"
```

The wizard supports:

- creating a new config
- editing default settings
- adding targets
- editing targets
- enabling or disabling targets
- removing targets
- configuring a Windows Scheduled Task
- saving `config.json`

You can also pass an explicit config path:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-ConfigWizard.ps1" -ConfigFile "C:\ArhivaTest\config.json"
```

For automated tests or scripted setup, pass an input file with one answer per line:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Start-ConfigWizard.ps1" -ConfigFile "C:\ArhivaTest\config.json" -InputFile "C:\ArhivaTest\wizard-input.txt"
```

## Windows Scheduled Task

The config wizard can create or update `scheduled-task.json`, which defines how Windows Task Scheduler should run `Start-FileArchive.ps1`.

Supported basic schedule options:

- `Daily`
- `Hourly`
- `Weekly`
- `AtStartup`

The wizard asks for:

- task name
- archive script path
- working directory
- schedule type
- start time
- interval
- days of week for weekly schedules
- Windows account, default `SYSTEM`
- run elevated
- enabled/disabled state

To register or update the task on Windows after creating `scheduled-task.json`:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ArhivaTest\Register-FileArchiveScheduledTask.ps1" -TaskConfigFile "C:\ArhivaTest\scheduled-task.json"
```

You can also let the wizard apply it immediately when prompted. Registering the task requires Windows and access to Task Scheduler permissions.

Example `scheduled-task.json`:

```json
{
  "TaskName": "NightlyFileArchive",
  "ScriptPath": "C:\\ArhivaTest\\Start-FileArchive.ps1",
  "WorkingDirectory": "C:\\ArhivaTest",
  "ScheduleType": "Daily",
  "StartTime": "02:30",
  "Interval": 1,
  "DaysOfWeek": "Monday",
  "UserId": "SYSTEM",
  "RunElevated": true,
  "Enabled": true
}
```

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
    "DateField": "LastWriteTime",
    "Extensions": [".txt", ".pdf", ".docx", ".bmp"],
    "MaxDepth": null,
    "MaxFilesPerRun": 10000,
    "ArchiveFolder": "Arhiva",
    "ArchiveZipEnabled": false,
    "ArchiveZipAfter": "1 year",
    "ArchiveZipGroupBy": "year",
    "RetentionEnabled": false,
    "RetentionYears": 7,
    "RetentionAction": "delete",
    "SecondaryStorage": "\\\\server\\long-term-archive",
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
| `OlderThanSeconds` | Archive files older than this many seconds, based on `DateField`. |
| `DateField` | Date used for age checks and `{year}` / `{month}` archive folders. Supported values: `LastWriteTime` and `CreationTime`. Default: `LastWriteTime`. |
| `Extensions` | File extensions that are allowed to be archived. |
| `MaxDepth` | Optional maximum folder depth to scan under the source folder. Default is `null`, which means unlimited. Root files have depth `0`; `Folder1\file.txt` has depth `1`; `Folder1\Folder2\Folder3\file.txt` has depth `3`. |
| `MaxFilesPerRun` | Optional maximum number of eligible files to process in one run. Default is `null`, which means unlimited. The alias `max_files_per_run` is also supported. Files are sorted by `CreationTime` ascending before the limit is applied, so the oldest files are processed first. |
| `ArchiveFolder` | Archive folder or archive path. Can include `{year}` and `{month}`. |
| `ArchivePath` | Optional explicit archive path. If set, it takes priority over `ArchiveFolder`. |
| `ArchiveZipEnabled` | Enables automatic ZIP compression of old archive folders. Default: `false`. Alias: `archive_zip_enabled`. |
| `ArchiveZipAfter` | Age threshold for ZIP compression, for example `"1 year"`, `"6 months"`, or `"30 days"`. Alias: `archive_zip_after`. |
| `ArchiveZipGroupBy` | ZIP grouping mode: `year` or `month`. Alias: `archive_zip_group_by`. |
| `RetentionEnabled` | Enables retention maintenance. Default: `false`. Alias: `retention_enabled`. |
| `RetentionYears` | Number of years to keep archives on primary storage. Alias: `retention_years`. |
| `RetentionAction` | Retention action: `delete` or `move`. Alias: `retention_action`. |
| `SecondaryStorage` | Destination for `RetentionAction: "move"`. Alias: `secondary_storage`. |
| `TestMode` | When `true`, logs what would happen without moving files. Aliases `DryRun` and `dry_run` are also supported. |
| `Enabled` | Enables or disables one target. |

Recommended `DateField`:

- Use `LastWriteTime` for normal document archives. This means the archive month follows the last time the file content changed.
- Use `CreationTime` only when the original creation date is reliable in your environment. On Windows, this value can change when files are copied, restored, downloaded, or extracted.

## Max Files Per Run

Use `MaxFilesPerRun` to limit how many eligible files are handled in a single run:

```json
{
  "Defaults": {
    "MaxFilesPerRun": 10000
  }
}
```

This snake_case form is also supported:

```json
{
  "max_files_per_run": 10000
}
```

Behavior:

- The script first finds all eligible files from enabled targets.
- It sorts candidates by `CreationTime` ascending.
- It selects at most `MaxFilesPerRun` files.
- Files not selected remain in place for the next run.
- In `TestMode: true`, the same limit is applied, but files are only logged as test actions and are not moved.

Example with 35,000 eligible files and `MaxFilesPerRun: 10000`:

```text
Run #1 -> 10,000 files
Run #2 -> 10,000 files
Run #3 -> 10,000 files
Run #4 ->  5,000 files
```

The run log includes selection counts and a summary:

```text
Files eligible for archive: 35000
Max files per run: 10000
Files selected: 10000
Files remaining: 25000

===== ARCHIVE RUN SUMMARY =====
Eligible files: 35000
Selected files: 10000
Successfully archived: 9985
Skipped: 8
Failed: 7
Remaining backlog: 25000
```

## Archive ZIP Compression

ZIP compression is disabled by default. Enable it with:

```json
{
  "Defaults": {
    "ArchiveZipEnabled": true,
    "ArchiveZipAfter": "1 year",
    "ArchiveZipGroupBy": "year"
  }
}
```

Snake_case aliases are also supported:

```json
{
  "archive_zip_enabled": true,
  "archive_zip_after": "1 year",
  "archive_zip_group_by": "month"
}
```

Supported grouping modes:

- `year`: compresses `Archive/2024/` into `Archive/2024.zip`. The ZIP keeps the month structure, for example `01/file.txt`.
- `month`: compresses `Archive/2024/01/` into `Archive/2024/01.zip`.

Safety behavior:

- ZIP compression only runs when enabled.
- Archive group age is checked from archived files' `CreationTime`.
- A group is compressed only when all files in that group are older than the configured threshold.
- Existing `.zip` archives are skipped, so repeated runs do not create duplicates.
- The script creates and validates a temporary ZIP before removing the original folder.
- If ZIP creation or validation fails, original files remain in place and the error is logged.
- In `TestMode` / `dry_run`, ZIP actions are logged but not executed.

## Retention Policy

Retention is disabled by default. Enable it with:

```json
{
  "Defaults": {
    "RetentionEnabled": true,
    "RetentionYears": 7,
    "RetentionAction": "delete"
  }
}
```

Move old archives to secondary storage:

```json
{
  "Defaults": {
    "RetentionEnabled": true,
    "RetentionYears": 7,
    "RetentionAction": "move",
    "SecondaryStorage": "\\\\server\\long-term-archive"
  }
}
```

Snake_case aliases are also supported:

```json
{
  "retention_enabled": true,
  "retention_years": 7,
  "retention_action": "move",
  "secondary_storage": "\\\\server\\long-term-archive"
}
```

Retention scans year archives under the archive base path, including both folders such as `2018/` and ZIP files such as `2018.zip`.

Safety behavior:

- Newer archives remain untouched.
- `delete` operations are logged with path, action, age, and status.
- `move` copies to secondary storage, validates the copied content, and only then removes the original.
- In `TestMode` / `dry_run`, retention actions are logged but not executed.
- Failure on one archive is logged and does not cause uncontrolled processing of other archives.

## Archive Folder Templates

The archive path can contain these tokens. Token values are taken from the configured `DateField`, not from the date when the script runs.

- `{year}`: four-digit year from the selected file date, for example `2026`
- `{month}`: two-digit month from the selected file date, for example `08`

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

## Docker Tests

The repository includes Docker-based fixture tests. They prepare a clean copy of the script, copy test files into it, run the archive process, and compare the resulting `data` folder with the expected folder tree.

Run all tests:

```bash
tests/run-tests.sh
```

Test layout:

```text
tests
|-- Dockerfile
|-- run-tests.ps1
|-- run-tests.sh
`-- test_data
    `-- <case-name>
        |-- input
        |   |-- config.json
        |   `-- data
        |-- expected
        |   `-- data
        |-- expected-dirs.txt
        |-- expected-exit-code.txt
        |-- expected-log-contains.txt
        |-- expected-log-exact.txt
        |-- expected-log-files.txt
        |-- expected-zip-entries.txt
        |-- expected-zips.txt
        `-- file-times.json
```

How it works:

- `input` is copied into a temporary application folder inside the container.
- `file-times.json` sets deterministic file timestamps before the script runs.
- `expected/data` is the expected final state after archiving.
- `expected-dirs.txt` is optional and lists expected empty directories under `data`, one path per line.
- `expected-exit-code.txt` is optional and contains the expected script exit code. Default is `0`.
- `expected-log-contains.txt` is optional and lists text fragments that must appear in the active or rotated logs.
- `expected-log-exact.txt` is optional and compares the active `FileArchive.log` line-by-line after removing timestamp prefixes. It supports `{APP_ROOT}` for the temporary application path.
- `expected-log-files.txt` is optional and lists log files that must exist under `Logs`, for example `FileArchive.log.1.zip`.
- `expected-zips.txt` is optional and lists expected ZIP files under `data`.
- `expected-zip-entries.txt` is optional and lists expected ZIP entries as `zip-path|entry-path`.
- `tests/test_results/<case-name>` is generated during the run and kept only when a test fails. It contains:
  - `actual/` with the real resulting `data` tree
  - `actual-tree.txt`
  - `expected-tree.txt`
  - `diff.txt`
  - script logs

To add a new test, create another folder under `tests/test_data`, add `input/config.json`, input files under `input/data`, expected files under `expected/data`, optional expected empty directories in `expected-dirs.txt`, optional expected exit code in `expected-exit-code.txt`, optional log checks in `expected-log-contains.txt` / `expected-log-exact.txt` / `expected-log-files.txt`, optional ZIP checks in `expected-zips.txt` / `expected-zip-entries.txt`, and timestamp entries in `file-times.json`.

## Notes

- Files are moved, not copied.
- Existing files inside the archive folder are skipped during future archive runs.
- Empty source subfolders left behind after successful moves are deleted. The source root folder itself is not deleted.
- If a destination file already exists, the script appends a timestamp to avoid overwriting it.
- Use `TestMode: true` before running a new configuration in production.
