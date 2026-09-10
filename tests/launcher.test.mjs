import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const launcherPath = fileURLToPath(new URL('../installer/launch.vbs', import.meta.url));
const launcherBytes = readFileSync(launcherPath);
const launcher = launcherBytes.toString('utf16le').replace(/^\uFEFF/, '');
const windows = { skip: process.platform !== 'win32' };
const vbsString = value => `"${value.replaceAll('"', '""')}"`;

// Execute the real VBScript control flow with external UI/process boundaries replaced.
// File I/O is real, but confined to one fresh temporary directory. No real app launches.
function runFixture({ autostart = true, running = 'none', failure = '', missingExe = false } = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), 'aie launcher space '));
  const script = path.join(directory, 'launch.vbs');
  const executable = path.join(directory, 'AIExcelCustom.exe');
  const trace = path.join(directory, 'trace.txt');
  const harness = `
Dim fixtureTrace, fixtureRunning, fixtureFailure
fixtureTrace = ${vbsString(trace)}
fixtureRunning = ${vbsString(running)}
fixtureFailure = ${vbsString(failure)}
Sub Record(value)
  Dim file
  Set file = CreateObject("Scripting.FileSystemObject").OpenTextFile(fixtureTrace, 8, True)
  file.WriteLine value
  file.Close
End Sub
Class FixtureShell
  Public CurrentDirectory
  Public Function ExpandEnvironmentStrings(value)
    ' Legacy code must not launch the installed application even in a red test.
    ExpandEnvironmentStrings = ${vbsString(directory)}
  End Function
  Public Function Run(command, style, wait)
    Record "run|" & command & "|" & style & "|" & wait & "|" & CurrentDirectory
    If fixtureFailure = "run" Then Err.Raise 5, "fixture", "SECRET_API_KEY_DO_NOT_LOG"
    Run = 0
  End Function
End Class
Class FixtureApplication
  Public Sub ShellExecute(command)
    Record "excel|" & command
  End Sub
End Class
Class FixtureProcess
  Public ExecutablePath
End Class
Class FixtureWmi
  Public Function ExecQuery(query)
    Dim processes, process
    Record "query|" & query
    If fixtureFailure = "wmi" Then Err.Raise 5, "fixture", "SECRET_API_KEY_DO_NOT_LOG"
    Set processes = CreateObject("Scripting.Dictionary")
    If fixtureRunning <> "none" Then
      Set process = New FixtureProcess
      Select Case fixtureRunning
        Case "same": process.ExecutablePath = ${vbsString(executable.toUpperCase())}
        Case "foreign": process.ExecutablePath = "C:\\Other App\\AIExcelCustom.exe"
        Case "unknown": process.ExecutablePath = Null
      End Select
      processes.Add process, True
    End If
    Set ExecQuery = processes
  End Function
End Class
Function FixtureCreateObject(name)
  Select Case LCase(name)
    Case "wscript.shell": Set FixtureCreateObject = New FixtureShell
    Case "shell.application": Set FixtureCreateObject = New FixtureApplication
    Case "scripting.filesystemobject": Set FixtureCreateObject = CreateObject(name)
    Case Else: Err.Raise 5, "fixture", "Unexpected COM object: " & name
  End Select
End Function
Function FixtureGetObject(name)
  Set FixtureGetObject = New FixtureWmi
End Function
Sub FixtureSleep(milliseconds)
  Record "sleep|" & milliseconds
End Sub
Function FixtureMsgBox(message, flags, title)
  Record "msgbox|" & title
  FixtureMsgBox = vbOK
End Function
`;
  const instrumented = launcher
    .replace(/^Option Explicit\s*$/mi, '')
    .replace(/\bCreateObject\(/gi, 'FixtureCreateObject(')
    .replace(/\bGetObject\(/gi, 'FixtureGetObject(')
    .replace(/\bMsgBox\b/gi, 'FixtureMsgBox')
    .replace(/WScript\.Sleep\b/gi, 'FixtureSleep');
  try {
    writeFileSync(script, '\uFEFFOption Explicit\r\n' + harness + '\r\n' + instrumented, 'utf16le');
    // This is deliberately not a valid executable; every Run call is intercepted above.
    if (!missingExe) writeFileSync(executable, 'TEST FIXTURE ONLY - DO NOT EXECUTE');
    const host = path.join(process.env.SystemRoot, 'System32', 'cscript.exe');
    const result = spawnSync(host, ['//Nologo', '//B', script, ...(autostart ? ['--autostart'] : [])], {
      encoding: 'utf8', timeout: 10000, windowsHide: true,
    });
    const events = existsSync(trace) ? readFileSync(trace, 'utf8').trim().split(/\r?\n/).filter(Boolean) : [];
    const logPath = path.join(directory, 'launch.log');
    const log = existsSync(logPath) ? readFileSync(logPath, 'utf8') : '';
    return { ...result, events, log, executable, directory };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function eventsOf(result, name) { return result.events.filter(event => event.startsWith(`${name}|`)); }
function assertSilent(result) {
  assert.deepEqual(eventsOf(result, 'msgbox'), [], 'Autostart must never display a dialog');
  assert.deepEqual(eventsOf(result, 'excel'), [], 'Autostart must never open Excel');
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
}

test('launcher retains UTF-16LE BOM for Windows Script Host', () => {
  assert.deepEqual([...launcherBytes.subarray(0, 2)], [0xff, 0xfe]);
  assert.ok(launcher.includes('服务'), 'Chinese prompts must decode correctly');
  assert.ok(!launcher.includes('\0'), 'Launcher must not be double-encoded');
});

test('autostart launches only the sibling service, hidden and non-waiting', windows, () => {
  const result = runFixture();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assertSilent(result);
  assert.deepEqual(eventsOf(result, 'run'), [`run|"${result.executable}" --autostart|0|False|${result.directory}`]);
  assert.deepEqual(eventsOf(result, 'sleep'), [], 'Autostart does not need the manual prompt delay');
  assert.equal(result.log, '');
});

test('manual launch retains the prompt, hidden service and one Excel launch', windows, () => {
  const result = runFixture({ autostart: false });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(eventsOf(result, 'run'), [`run|"${result.executable}"|0|False|${result.directory}`]);
  assert.equal(eventsOf(result, 'msgbox').length, 1);
  assert.deepEqual(eventsOf(result, 'excel'), ['excel|excel.exe']);
  assert.deepEqual(eventsOf(result, 'sleep'), ['sleep|1500']);
});

test('same executable path prevents a duplicate service in autostart and manual modes', windows, () => {
  for (const autostart of [true, false]) {
    const result = runFixture({ autostart, running: 'same' });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.deepEqual(eventsOf(result, 'run'), []);
    if (autostart) assertSilent(result);
    else {
      assert.equal(eventsOf(result, 'msgbox').length, 1);
      assert.deepEqual(eventsOf(result, 'excel'), ['excel|excel.exe']);
    }
  }
});

test('a same-name executable elsewhere does not suppress this installation', windows, () => {
  const result = runFixture({ running: 'foreign' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assertSilent(result);
  assert.deepEqual(eventsOf(result, 'run'), [`run|"${result.executable}" --autostart|0|False|${result.directory}`]);
});

test('unreadable unrelated process paths do not match this service', windows, () => {
  const result = runFixture({ running: 'unknown' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assertSilent(result);
  assert.equal(eventsOf(result, 'run').length, 1);
});

for (const failure of ['wmi', 'run', 'missing']) {
  test(`autostart ${failure} failure is silent and logs only a brief safe diagnostic`, windows, () => {
    const result = runFixture({ failure, missingExe: failure === 'missing' });
    assert.equal(result.status, 1, 'Launch errors must produce a nonzero exit status');
    assertSilent(result);
    assert.ok(result.log.length > 0 && result.log.length < 512, 'A short launch.log must explain the failed stage');
    assert.doesNotMatch(result.log, /SECRET_API_KEY_DO_NOT_LOG/);
    if (failure !== 'run') assert.deepEqual(eventsOf(result, 'run'), []);
  });
}
