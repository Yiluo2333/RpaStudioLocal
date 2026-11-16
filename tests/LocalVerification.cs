using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Collections;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Threading;
using Newtonsoft.Json.Linq;
using RpaService.Studio;
using RpaStudioShare;

// Compiled only into the development test host. Tests run on disposable copies.
internal static class LocalVerification {
    public static int ExitCode=1;
    const BindingFlags All=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static;
    static object Get(object o,string p) {return o.GetType().GetProperty(p,All).GetValue(o,null);}
    static void Assert(bool condition,string message) {if(!condition)throw new Exception(message);}
    static bool Same(object a,object b) {return JToken.DeepEquals(JToken.Parse(RpaUtil.Serialization.JsonSerialization.Serialize(a)),JToken.Parse(RpaUtil.Serialization.JsonSerialization.Serialize(b)));}
    public static string CreateBlank(string root) {
        string parent=Path.GetFullPath(Path.Combine(root,"..","validation","new-"+Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(parent);
        var vm=new RpaStudioUI.ViewModel.HomePageProjectViewModel();
        vm.GetType().GetMethod("NewBlankProject",All).Invoke(vm,new object[]{parent,"本地新项目"});
        string path=Path.Combine(parent,"本地新项目","本地新项目.proj");
        Assert(File.Exists(path),"Original new-project action failed.");
        File.WriteAllText(Path.Combine(root,"LocalConfig","new-project-verification.txt"),"PASS: Original new blank project created and saved.\n");
        return path;
    }
    public static int RunBlank(string root) {
        string path=CreateBlank(root);
        var service=new ProjectService();service.Load(path);
        var model=service.GetDeepModel();
        Assert(!model.IsReportEnabled,"Test flow must not send reports.");
        var start=model.MainFlowModel.SubNodes.First(n=>n is RpaModel.Studio.FlowNodeStartModel);
        var end=model.MainFlowModel.SubNodes.First(n=>n is RpaModel.Studio.FlowNodeEndModel);
        var execution=new RpaModel.Studio.FlowNodeExecuteModel(Guid.NewGuid().ToString("N")) {Name="本地组件自检"};
        var commandAssembly=Assembly.LoadFrom(Path.Combine(root,"CommandLibs","RpaFlowCommand","1.0.0.0","RpaFlowCommand.dll"));
        var comment=(RpaModel.Studio.AbstractScriptCommandModel)Activator.CreateInstance(commandAssembly.GetType("RpaFlowCommand.Model.CommentCommandModel",true));
        comment.Parameters=new Dictionary<string,RpaModel.Studio.CommandParameterModel> {
            {"Comment",new RpaModel.Studio.CommandParameterModel {Value="本地组件自检"}}
        };
        execution.ScriptActions.Add(new RpaModel.Studio.Script.ScriptActionModel {ScriptCommand=comment});
        model.MainFlowModel.SubNodes.Add(execution);execution.SetParent(model.MainFlowModel);
        start.SetNext(execution);execution.SetNext(end);
        var type=Assembly.Load("RpaEngine").GetType("RpaEngine.ScriptRunnerService",true);
        var runner=Activator.CreateInstance(type,new object[]{model});
        type.GetMethod("Run").Invoke(runner,null);
        var result=Get(runner,"Result");
        bool success=(bool)Get(result,"Success");
        File.WriteAllText(Path.Combine(root,"LocalConfig","engine-verification.txt"),success ? "PASS: Newly generated start -> bundled comment command -> end flow executed successfully with the original engine in offline mode. No business project was run." : "FAIL: Original engine did not complete the test flow. "+Get(result,"Cause"));
        var dispose=type.GetMethod("Dispose");if(dispose!=null)dispose.Invoke(runner,null);
        return success?0:1;
    }
    public static void Attach(Application app,Window window,string root,string project) {
        Assert(project!=null && Path.GetFullPath(project).StartsWith(Path.GetFullPath(Path.Combine(root,"..","validation"))+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase),"Only disposable validation projects may be used.");
        int attempts=0;
        var timer=new DispatcherTimer {Interval=TimeSpan.FromSeconds(1)};
        timer.Tick+=(s,e)=> {
            if(RpaStudioSharedClass.Instance.MainFlowService==null && ++attempts<30)return;
            timer.Stop();
            var lines=new List<string>();
            try {
                var shared=RpaStudioSharedClass.Instance;
                Assert(shared.MainFlowService!=null,"Main flow was not initialized.");
                Assert(ScriptCommandService.Instance.GetIdeCommandMetas().Count()==322,"Expected 322 bundled command definitions.");
                lines.Add("PASS: 322 command definitions and original main flow initialized.");
                var vm=window.DataContext;
                var helpers=(IList)vm.GetType().GetField("_tableItemHelpList",All).GetValue(vm);
                var visited=new HashSet<string>();
                var nodeType=Assembly.Load("RpaDiagrams").GetType("RpaDiagrams.Controls.Node",true);
                var open=vm.GetType().GetMethod("ItemDoubleClick",All);
                int openCount=0;
                for(int i=0;i<helpers.Count && i<100;i++) {
                    var helper=helpers[i];
                    var flowProp=helper.GetType().GetProperty("FlowchartUIModel");
                    if(flowProp==null)continue;
                    var flow=flowProp.GetValue(helper,null);
                    if(flow==null)continue;
                    foreach(var model in ((IEnumerable)Get(flow,"Nodes")).Cast<object>().ToArray()) {
                        string id=(string)Get(model,"Id");
                        if(!visited.Add(id))continue;
                        bool nested=Directory.GetFiles(shared.CurrentProjectService.DocumentDir,id+".flow",SearchOption.AllDirectories).Length>0;
                        bool script=Directory.GetFiles(shared.CurrentProjectService.DocumentDir,id+".script",SearchOption.AllDirectories).Length>0;
                        if(!nested && !script)continue;
                        var node=Activator.CreateInstance(nodeType);
                        nodeType.GetProperty("ModelElement",All).SetValue(node,model,null);
                        open.Invoke(vm,new object[]{node,new RoutedEventArgs(System.Windows.Controls.Control.MouseDoubleClickEvent)});
                        openCount++;
                    }
                }
                Assert(openCount>0,"No nested flow or execution unit was opened.");
                lines.Add("PASS: Original nested editor opened "+openCount+" child flows / execution units; "+helpers.Count+" tabs.");
                int commands=0,scriptCount=0;
                foreach(string path in Directory.GetFiles(shared.CurrentProjectService.DocumentDir,"*.script",SearchOption.AllDirectories)) {
                    var service=new ScriptService();service.Load(path);
                    var before=JToken.Parse(RpaUtil.Serialization.JsonSerialization.Serialize(service.FlowNodeExecuteModel));
                    commands+=((JContainer)before).Descendants().OfType<JProperty>().Count(p=>p.Name=="ScriptCommand");scriptCount++;
                    service.Save();
                    var reread=new ScriptService();reread.Load(path);
                    Assert(JToken.DeepEquals(before,JToken.Parse(RpaUtil.Serialization.JsonSerialization.Serialize(reread.FlowNodeExecuteModel))),"Script changed during save/reload.");
                }
                Assert(commands>0,"No legacy commands were read.");
                lines.Add("PASS: "+scriptCount+" legacy scripts, "+commands+" actions, parameters preserved across save/reload.");
                var proj=shared.CurrentProjectService;
                var beforeProject=JToken.Parse(RpaUtil.Serialization.JsonSerialization.Serialize(proj.ProjectModel));
                proj.Save();var reproject=new ProjectService();reproject.Load(proj.DocumentFile);
                Assert(JToken.DeepEquals(beforeProject,JToken.Parse(RpaUtil.Serialization.JsonSerialization.Serialize(reproject.ProjectModel))),"Project changed during save/reload.");
                lines.Add("PASS: Original project metadata and variables preserved across save/reload.");
                lines.Add("Business execution: not invoked.");
                ExitCode=0;
            } catch(Exception ex) {while(ex is TargetInvocationException && ex.InnerException!=null)ex=ex.InnerException;lines.Add("FAIL: "+ex);}
            File.WriteAllLines(Path.Combine(root,"LocalConfig","editor-verification.txt"),lines);
            app.Shutdown(ExitCode);
        };
        timer.Start();
    }
}
