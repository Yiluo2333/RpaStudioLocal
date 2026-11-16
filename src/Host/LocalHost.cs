using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization;
using System.Windows;
using System.Windows.Threading;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Collections.Generic;
using RpaModel;
using RpaModel.Studio;
using RpaService.Interface;
using RpaService.Studio;
using RpaStudioShare;

// Original assemblies are loaded unchanged. Local settings never use the vendor's
// AppData profile, and no server identity or license is manufactured here.
internal sealed class LocalConfigSeed : AbstractConfigService {
    public LocalConfigSeed(string folder) {
        Directory.CreateDirectory(folder);
        SystemConfigDir=UserConfigDir=folder;
        SystemConfigFile=Path.Combine(folder,"system.config");
        UserConfigFile=Path.Combine(folder,"user.config");
        if(File.Exists(SystemConfigFile)) LoadSystemConfig<StudioSystemConfigModel>();
        else SaveSystemConfig(new StudioSystemConfigModel {
            Language="zh-CN", IsDisplayDebug=true, IsSuspendedBall=false,
            IsAutoCloseDebug=false, HotKeyStop="F10", HotKeySuspendAndContinue="F11",
            LogDay="7", DeviceId=Guid.NewGuid().ToString("N")
        });
        if(File.Exists(UserConfigFile)) LoadUserConfig<StudioUserConfigModel>();
        else SaveUserConfig(new StudioUserConfigModel());
    }
}

internal static class LocalHost {
    static string root=Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar)).FullName;
    static string logPath=Path.Combine(root,"LocalConfig","host.log");
    static object configSeed;
    static readonly string[] RemovedCommands={"UserInfoClickCommand","NavigateToTemplateCommand","LaunchCommand","FileLaunchCommand","UserCommandLaunchCommand","FindMoreCommandsCommand","TemplateClickCommand","MoreTemplateCommand"};
    static readonly HashSet<object> configured=new HashSet<object>();
    sealed class ActionCommand : ICommand {
        readonly Action<object> action;
        public ActionCommand(Action<object> action) {this.action=action;}
        public bool CanExecute(object p) {return true;}
        public void Execute(object p) {action(p);}
        public event EventHandler CanExecuteChanged {add{} remove{}}
    }
    sealed class UnavailableCommand : ICommand {
        public bool CanExecute(object p) {return false;}
        public void Execute(object p) {}
        public event EventHandler CanExecuteChanged {add{} remove{}}
    }
    static readonly ICommand unavailable=new UnavailableCommand();
    const BindingFlags All=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static;
    static void Log(string s) {Directory.CreateDirectory(Path.GetDirectoryName(logPath));File.AppendAllText(logPath,DateTime.Now.ToString("s")+" "+s+Environment.NewLine);}
    static Exception Unwrap(Exception e) {while(e is TargetInvocationException && e.InnerException!=null)e=e.InnerException;return e;}
    static void InstallLocalConfig() {
        var seed=new LocalConfigSeed(Path.Combine(root,"LocalConfig")); configSeed=seed;
        var local=(StudioConfigService)FormatterServices.GetUninitializedObject(typeof(StudioConfigService));
        foreach(var f in typeof(AbstractConfigService).GetFields(BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.Public)) f.SetValue(local,f.GetValue(seed));
        GC.SuppressFinalize(seed);
        System.Runtime.CompilerServices.RuntimeHelpers.RunClassConstructor(typeof(StudioConfigService).TypeHandle);
        typeof(StudioConfigService).GetField("Lazy",All).SetValue(null,new Lazy<StudioConfigService>(()=>local));
    }
    static void InitializeLocal() {
        InstallLocalConfig();
        RpaService.SystemSettingsService.Instance.SetClientType(ClientTypeConstants.Ide);
        // The original editor attempts extension installation on first launch.
        // Suppress that optional deployment step in this isolated workspace.
        StudioSystemSettingsService.Instance.InsertOrUpdate("IsRegistedChromePlugin","1");
        // The original runner already exposes an offline transport. Its factory
        // requires a syntactically valid URL even when no connection is opened.
        StudioSystemSettingsService.Instance.InsertOrUpdate("WebsocketUrl","ws://127.0.0.1:1");
        StudioSystemSettingsService.Instance.GetSettings();
        var transportType=Assembly.Load("RpaEngine").GetType("RpaEngine.Remote.RpaEngineWebsocketClientService",true);
        var transport=transportType.GetProperty("Instance").GetValue(null,null);
        transportType.GetMethod("Offline").Invoke(transport,null);
        RpaResource.Localization.LanguageManager.Instance.SetLanguage("zh-CN");
        var shared=RpaStudioSharedClass.Instance;
        shared.UserData=new UserModel {UserId="local",UserAccount="local",DisplayName="本地工作区"};
        shared.CurrentUserData=new StudioCurrentUserModel {UserId="local",UserAccount="local",DisplayName="本地工作区"};
        RpaService.Client.ClientCurrentUserSettingsService.Instance.CurrentUserModel=new RpaModel.Client.ClientCurrentUserModel {
            UserId="rpa-local-"+StudioConfigService.Instance.CurrentSystemConfig.DeviceId,
            UserAccount="local",DisplayName="本地工作区"
        };
        StudioCommandLineService.Instance.Update(new StudioCommandLineParameterModel());
        Log("Local profile initialized; no cloud session.");
    }
    static Application CreateApp() {
        var asm=Assembly.LoadFrom(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"RpaStudio.exe"));
        var type=asm.GetType("RpaStudio.App",true);
        var app=(Application)Activator.CreateInstance(type,true);
        type.GetMethod("InitializeComponent",All).Invoke(app,null);
        var method=type.GetMethod("Application_Startup",All);
        app.Startup-=(StartupEventHandler)Delegate.CreateDelegate(typeof(StartupEventHandler),app,method);
        app.DispatcherUnhandledException+=(s,e)=> {Log(Unwrap(e.Exception).ToString());};
        EventManager.RegisterClassHandler(typeof(FrameworkElement),FrameworkElement.LoadedEvent,new RoutedEventHandler(SimplifyElement));
        return app;
    }
    static void SimplifyElement(object sender,RoutedEventArgs e) {
        var element=sender as FrameworkElement;
        if(element==null || !Object.ReferenceEquals(e.OriginalSource,sender))return;
        object vm=element.DataContext;
        if(vm!=null && vm.GetType().Assembly.GetName().Name=="RpaStudioUI" && configured.Add(vm)) {
            foreach(string name in RemovedCommands) {
                var p=vm.GetType().GetProperty(name);
                if(p!=null && p.CanWrite && p.PropertyType==typeof(ICommand)) SetAndNotify(vm,name,unavailable);
            }
            if(vm.GetType().FullName=="RpaStudioUI.ViewModel.HomePageProjectViewModel") {
                // Original Localize() fetches online store recommendations. Keep
                // only its local page initialization and Chinese labels.
                SetAndNotify(vm,"LoadedCommand",new ActionCommand(p=> {
                    vm.GetType().GetField("_homePageProject",All).SetValue(vm,p);
                    vm.GetType().GetMethod("LoadRecentProjects",All).Invoke(vm,null);
                    vm.GetType().GetMethod("ChangeRecentProjectZone",All).Invoke(vm,null);
                }));
                SetAndNotify(vm,"TitleNewBlankProject","新建空白项目");
                SetAndNotify(vm,"TitleNewBlankFlow","新建一个空白流程");
                SetAndNotify(vm,"TitleNewProject","新建项目");
                SetAndNotify(vm,"TitleRecentProjects","最近项目");
                SetAndNotify(vm,"TooltipPin","固定项目");
                SetAndNotify(vm,"TooltipRemoveRecentProject","移出最近项目");
            }
        }
        var content=element as ContentControl;
        if(content!=null && content.Content is string && new[]{"模板","更多模板","获取更多"}.Contains((string)content.Content)) element.Visibility=Visibility.Collapsed;
        var text=element as TextBlock;
        if(text!=null && new[]{"模板","更多模板","获取更多","发布","发布 用户命令"}.Contains(text.Text)) {
            DependencyObject parent=text;
            while((parent=System.Windows.Media.VisualTreeHelper.GetParent(parent))!=null) {
                if(parent is ButtonBase || parent is MenuItem) {((UIElement)parent).Visibility=Visibility.Collapsed;break;}
            }
        }
        if(text!=null && text.Text=="从模板新建") {
            var parent=System.Windows.Media.VisualTreeHelper.GetParent(text) as UIElement;
            if(parent!=null)parent.Visibility=Visibility.Collapsed;
        }
        DependencyProperty commandProperty=element is ButtonBase ? ButtonBase.CommandProperty : element is MenuItem ? MenuItem.CommandProperty : null;
        if(commandProperty!=null) {
            var binding=BindingOperations.GetBinding(element,commandProperty);
            string name=binding==null || binding.Path==null ? null : binding.Path.Path;
            if(RemovedCommands.Contains(name)) {
                // A local value also survives old view models toggling visibility.
                BindingOperations.ClearBinding(element,UIElement.VisibilityProperty);
                element.Visibility=Visibility.Collapsed;
                BindingOperations.ClearBinding(element,commandProperty);
                element.SetValue(commandProperty,unavailable);
            }
        }
    }
    static void SetAndNotify(object vm,string name,object value) {
        var p=vm.GetType().GetProperty(name);
        if(p==null || !p.CanWrite)return;
        p.SetValue(vm,value,null);
        var notify=typeof(RpaUI.ObserveObject).GetMethod("OnPropertyChanged",All,null,new[]{typeof(string)},null);
        if(notify!=null)notify.Invoke(vm,new object[]{name});
    }
    static void ApplyIcon(Window w) {
        try {
            string ico=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ico","TaskBar.ico");
            if(File.Exists(ico))w.Icon=System.Windows.Media.Imaging.BitmapFrame.Create(new Uri(ico,UriKind.Absolute));
        }catch{}
    }
    static void LoadProject(object homeVm,string path) {
        homeVm.GetType().GetMethod("LoadProject",All).Invoke(homeVm,new object[]{Path.GetFullPath(path),Path.GetDirectoryName(Path.GetDirectoryName(Path.GetFullPath(path)))});
        Log("Project loaded with original parser.");
    }
    [STAThread] public static int Main(string[] args) {
        try {
            Directory.SetCurrentDirectory(AppDomain.CurrentDomain.BaseDirectory);
            AppDomain.CurrentDomain.UnhandledException+=(s,e)=>Log(((Exception)e.ExceptionObject).ToString());
            InitializeLocal();
            var app=CreateApp();
            var home=new RpaStudioUI.View.RpaStudioWinHomeView();
            ApplyIcon(home);
            Log("Original home constructed.");
            bool verify=args.Contains("--verify");
            string project=args.FirstOrDefault(a=>a.EndsWith(".proj",StringComparison.OrdinalIgnoreCase));
#if VALIDATION
            if(args.Contains("--verify-engine"))return LocalVerification.RunBlank(root);
            if(args.Contains("--verify-new"))project=LocalVerification.CreateBlank(root);
#endif
            if(project==null)SetAndNotify(home.DataContext,"GobackVisible",Visibility.Collapsed);
            home.Activated+=(s,e)=> {
                SetAndNotify(home.DataContext,"GobackVisible",RpaStudioSharedClass.Instance.CurrentProjectService==null?Visibility.Collapsed:Visibility.Visible);
                var frame=home.FindName("hostName") as Frame;
                var page=frame==null?null:frame.Content as FrameworkElement;
                if(page!=null && page.DataContext!=null && page.DataContext.GetType().FullName=="RpaStudioUI.ViewModel.HomePageProjectViewModel")page.DataContext.GetType().GetMethod("LoadRecentProjects",All).Invoke(page.DataContext,null);
            };
            if(verify) {
                var metas=ScriptCommandService.Instance.GetIdeCommandMetas();
                Log("Command metadata count="+metas.Count());
                var tree=RpaStudioUI.Service.TreeDataService.Instance;
                Log("Command tree nodes="+tree.AllNodes.Count);
                if(project!=null) LoadProject(home.DataContext,project);
                File.WriteAllText(Path.Combine(root,"LocalConfig","verify.ok"),"Commands="+metas.Count()+"; TreeNodes="+tree.AllNodes.Count+"; Project="+(project!=null));
                Log("Verification completed.");
                return 0;
            }
            var manager=RpaStudioUI.RpaWindowManager.GetInstance();
            manager.Register<RpaStudioUI.View.RpaStudioWinHomeView>(home);
            Window window=home;
            if(project!=null) {LoadProject(home.DataContext,project);window=new RpaStudioUI.RpaStudioWinMainView();ApplyIcon(window);manager.Register<RpaStudioUI.RpaStudioWinMainView>(window);}
            manager.CurrentWindow=window;
#if VALIDATION
            if(args.Contains("--verify-editor")) LocalVerification.Attach(app,window,root,project);
#endif
            Log("Starting original window.");
            app.Run(window);
            GC.KeepAlive(configSeed);
#if VALIDATION
            if(args.Contains("--verify-editor"))return LocalVerification.ExitCode;
#endif
            return 0;
        } catch(Exception e) {
            Log(Unwrap(e).ToString());
            if(!args.Contains("--verify")) MessageBox.Show("本地版启动失败，请查看 LocalConfig\\host.log。\n"+Unwrap(e).Message,"RPA 本地版");
            return 1;
        }
    }
}
