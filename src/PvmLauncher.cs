using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("PVM for Windows")]
[assembly: AssemblyCompany("PVM")]
[assembly: AssemblyProduct("PVM for Windows")]
[assembly: AssemblyDescription("Python version manager for Windows")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class PvmLauncher
{
    private static string Quote(string value)
    {
        if (value.Length > 0 && value.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            return value;
        var result = new System.Text.StringBuilder("\"");
        int slashes = 0;
        foreach (char ch in value)
        {
            if (ch == '\\') { slashes++; continue; }
            if (ch == '"') { result.Append('\\', slashes * 2 + 1).Append('"'); slashes = 0; continue; }
            result.Append('\\', slashes).Append(ch);
            slashes = 0;
        }
        result.Append('\\', slashes * 2).Append('"');
        return result.ToString();
    }

    private static int Main(string[] args)
    {
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "pvm.ps1");
        if (!File.Exists(script))
        {
            Console.Error.WriteLine("PVM: pvm.ps1 was not found beside pvm.exe. Run PVM-Setup.exe to install PVM.");
            return 1;
        }

        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");
        var command = new System.Text.StringBuilder("-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File ");
        command.Append(Quote(script));
        foreach (string arg in args) command.Append(' ').Append(Quote(arg));

        var start = new ProcessStartInfo(powershell, command.ToString());
        start.UseShellExecute = false;
        start.CreateNoWindow = false;
        start.WorkingDirectory = Environment.CurrentDirectory;
        using (Process process = Process.Start(start))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }
}
