using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class BundleLauncher {
    static string Hash(Stream stream) {using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();}
    static string FileHash(string path) {using(var s=File.OpenRead(path))return Hash(s);}
    static string SafePath(string root,string relative) {
        string path=Path.GetFullPath(Path.Combine(root,relative.Replace('/',Path.DirectorySeparatorChar)));
        if(!path.StartsWith(root.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Invalid bundled path.");
        return path;
    }
    // Windows command-line quoting, including trailing backslashes before quotes.
    static string Quote(string arg) {
        var b=new StringBuilder("\"");int slashes=0;
        foreach(char c in arg) {
            if(c=='\\') {slashes++;continue;}
            if(c=='\"') {b.Append('\\',slashes*2+1);b.Append(c);slashes=0;continue;}
            b.Append('\\',slashes);slashes=0;b.Append(c);
        }
        b.Append('\\',slashes*2);return b.Append('"').ToString();
    }
    [STAThread] public static int Main(string[] args) {
        bool verify=args.Any(a=>a.StartsWith("--verify",StringComparison.OrdinalIgnoreCase));
        string baseDir=Environment.GetEnvironmentVariable("RPA_LOCAL_RUNTIME");
        if(String.IsNullOrEmpty(baseDir))baseDir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"RpaStudioLocal");
        Form splash=null;
        try {
            baseDir=Path.GetFullPath(baseDir);Directory.CreateDirectory(baseDir);
            string id;
            using(var payload=Assembly.GetExecutingAssembly().GetManifestResourceStream("runtime.zip"))id=Hash(payload);
            string root=Path.Combine(baseDir,"Versions",id.Substring(0,16));
            int restored=0,total=0;
            ProgressBar progress=null;Label status=null;
            if(!verify) {
                splash=new Form {Text="RPA 本地版",Width=440,Height=140,StartPosition=FormStartPosition.CenterScreen,FormBorderStyle=FormBorderStyle.FixedDialog,ControlBox=false};
                try{splash.Icon=System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);}catch{}
                status=new Label {Text="正在准备本地组件，首次启动可能需要片刻…",Left=20,Top=20,Width=390,Height=25};
                progress=new ProgressBar {Left=20,Top=55,Width=390,Height=20,Maximum=1};
                splash.Controls.Add(status);splash.Controls.Add(progress);splash.Show();Application.DoEvents();
            }
            using(var gate=new Mutex(false,"Local\\RpaStudioLocal-Install-"+id.Substring(0,16))) {
                bool acquired=false;
                try {acquired=gate.WaitOne(TimeSpan.FromSeconds(30));}
                catch(AbandonedMutexException) {acquired=true;}
                if(!acquired)throw new IOException("另一个窗口正在准备运行组件，请稍后重试。");
                try {
                    Directory.CreateDirectory(root);
                    using(var payload=Assembly.GetExecutingAssembly().GetManifestResourceStream("runtime.zip"))
                    using(var archive=new ZipArchive(payload,ZipArchiveMode.Read)) {
                        var manifest=archive.GetEntry("bundle.sha256");
                        if(manifest==null)throw new InvalidDataException("缺少组件清单。");
                        string[] entries;
                        using(var r=new StreamReader(manifest.Open(),Encoding.UTF8))entries=r.ReadToEnd().Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries);
                        if(progress!=null)progress.Maximum=entries.Length;
                        foreach(string line in entries) {
                            if(line.Length<67 || line.Substring(64,2)!="  ")throw new InvalidDataException("组件清单损坏。");
                            string expected=line.Substring(0,64),relative=line.Substring(66);
                            string dest=SafePath(root,relative);total++;
                            if(progress!=null && (total%10==0 || total==entries.Length)) {progress.Value=total;status.Text="正在准备本地组件（"+total+" / "+entries.Length+"）…";Application.DoEvents();}
                            if(File.Exists(dest) && FileHash(dest)==expected)continue;
                            var entry=archive.GetEntry(relative);
                            if(entry==null)throw new InvalidDataException("缺少组件："+relative);
                            Directory.CreateDirectory(Path.GetDirectoryName(dest));
                            string temp=dest+".prepare-"+Guid.NewGuid().ToString("N");
                            try {
                                using(var input=entry.Open())using(var output=File.Create(temp))input.CopyTo(output);
                                if(FileHash(temp)!=expected)throw new InvalidDataException("组件校验失败："+relative);
                                if(File.Exists(dest))File.Replace(temp,dest,null);else File.Move(temp,dest);
                                restored++;
                            } finally {if(File.Exists(temp))File.Delete(temp);}
                        }
                    }
                    foreach(string folder in new[]{"Config","Scripts","UserCommandLibs","LocalConfig"})Directory.CreateDirectory(Path.Combine(root,folder));
                } finally {gate.ReleaseMutex();}
            }
            File.WriteAllText(Path.Combine(baseDir,"last-check.txt"),"Runtime="+root+Environment.NewLine+"VerifiedFiles="+total+Environment.NewLine+"RestoredFiles="+restored+Environment.NewLine+"PayloadSHA256="+id+Environment.NewLine,Encoding.UTF8);
            string host=Path.Combine(root,"net461","RpaStudioLocal.exe");
            var start=new ProcessStartInfo(host,String.Join(" ",args.Select(Quote))) {UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(host),CreateNoWindow=verify};
            using(var process=Process.Start(start)) {
                if(splash!=null)splash.Dispose();
                if(!verify)return 0;
                process.WaitForExit();
                File.AppendAllText(Path.Combine(baseDir,"last-check.txt"),"HostExitCode="+process.ExitCode+Environment.NewLine);
                return process.ExitCode;
            }
        } catch(Exception e) {
            if(splash!=null)try{splash.Dispose();}catch{}
            try {Directory.CreateDirectory(baseDir);File.WriteAllText(Path.Combine(baseDir,"launcher-error.txt"),e.ToString());}catch{}
            if(!verify)MessageBox.Show("组件准备失败："+e.Message+"\n请关闭本地版后重试。","RPA 本地版",MessageBoxButtons.OK,MessageBoxIcon.Error);
            return 1;
        }
    }
}
