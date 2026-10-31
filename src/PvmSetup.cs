using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

internal static class PvmSetup
{
    private static void Extract(string resourceName, string path)
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
        {
            if (input == null) throw new InvalidOperationException("Missing installer payload: " + resourceName);
            using (FileStream output = File.Create(path)) input.CopyTo(output);
        }
    }

    private static int Main(string[] args)
    {
        string work = Path.Combine(Path.GetTempPath(), "PVM-Setup-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(work);
            Extract("payload.install.ps1", Path.Combine(work, "install.ps1"));
            Extract("payload.pvm.ps1", Path.Combine(work, "pvm.ps1"));
            Extract("payload.pvm.cmd", Path.Combine(work, "pvm.cmd"));
            Extract("payload.pvm.exe", Path.Combine(work, "pvm.exe"));

            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            string arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" +
                Path.Combine(work, "install.ps1") + "\"";
            foreach (string arg in args) arguments += " \"" + arg.Replace("\"", "\\\"") + "\"";

            var start = new ProcessStartInfo(powershell, arguments);
            start.UseShellExecute = false;
            start.CreateNoWindow = false;
            start.WorkingDirectory = work;
            using (Process process = Process.Start(start))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("PVM setup failed: " + ex.Message);
            return 1;
        }
        finally
        {
            try { if (Directory.Exists(work)) Directory.Delete(work, true); }
            catch { }
        }
    }
}
