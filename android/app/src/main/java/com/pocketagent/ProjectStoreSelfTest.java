package com.pocketagent;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;
/** Explicit ADB/app_process self-test. Only its unique /data/local/tmp scratch directory is touched. */
public final class ProjectStoreSelfTest {
    private static int checks;
    private static void check(boolean value,String name){if(!value)throw new AssertionError(name);checks++;}
    public static void main(String[] args)throws Exception{System.out.println(run(new File("/data/local/tmp/asterhand-services-test-"+UUID.randomUUID())));}
    public static JSONObject run(android.content.Context context)throws Exception{return run(new File(context.getCacheDir(),"project-selftest-"+UUID.randomUUID()));}
    private static synchronized JSONObject run(File scratch)throws Exception{
        checks=0;if(!scratch.mkdirs())throw new IOException("Unable to create isolated test directory");
        try{
            File files=new File(scratch,"app"),workspace=new File(scratch,"workspace");files.mkdirs();workspace.mkdirs();
            ProjectStore store=new ProjectStore(files,workspace);String original=store.currentProject().getString("id");
            check(new File(store.currentProject().getString("workspace")).getCanonicalFile().equals(new File(new File(workspace,"Projects"),original).getCanonicalFile()),"new default project has its own workspace");
            JSONObject a=store.createProject("甲"),b=store.createProject("乙");String aid=a.getString("id"),bid=b.getString("id"),achat=a.getJSONArray("chats").getJSONObject(0).getString("id"),bchat=b.getJSONArray("chats").getJSONObject(0).getString("id");
            JSONArray history=new JSONArray().put(new JSONObject().put("role","user").put("content","隔离测试"));
            check(store.saveChat(aid,achat,history,"A"),"save background target");check(store.currentProject().getString("id").equals(bid),"background save must not select target");check(store.currentChat().getJSONArray("history").length()==0,"project isolation");
            check(store.renameProject(aid,"甲改名"),"rename project");check(store.renameChat(achat,"新对话：手动标题"),"rename chat");check(store.saveChat(aid,achat,history,"A2"),"save renamed chat");store.selectChat(achat);check(store.currentChat().getString("title").equals("新对话：手动标题"),"manual title must not be overwritten");
            JSONObject copy=store.currentProject();copy.put("name","should not change");check(store.currentProject().getString("name").equals("甲改名"),"public copies must not mutate store");
            ProjectStore reload=new ProjectStore(files,workspace);check(reload.currentProject().getString("id").equals(aid),"cross-instance selection shares live state");reload.selectProject(bid);check(store.currentProject().getString("id").equals(bid),"cross-instance edits stay consistent");store.selectChat(achat);check(new JSONObject(read(new File(files,"projects.json"))).getString("currentChatID").equals(achat),"committed index is on disk");check(reload.currentChat().getString("id").equals(achat),"selection persists");check(reload.currentChat().getString("transcript").equals("A2"),"history persists");
            char[] large=new char[730000];Arrays.fill(large,'x');JSONArray oversized=new JSONArray().put(new JSONObject().put("role","user").put("content",new String(large)));check(!reload.saveChat(aid,achat,oversized,"lost"),"oversized save rejected");check(reload.currentChat().getString("transcript").equals("A2"),"oversized save preserves history");
            String extra=reload.createChat().getString("id");check(reload.deleteChats(Arrays.asList(achat,extra))==2,"batch chat deletion");check(reload.currentChat()!=null,"empty project receives new chat");
            File loose=new File(workspace,"keep.txt");write(loose,"preserved");JSONObject deleted=reload.deleteProject(original,true);check(deleted.getInt("deleted")==1,"default project record deletion");check(deleted.getJSONArray("file_errors").length()==0&&loose.isFile(),"new default deletion leaves unrelated parent files");
            File owned=new File(b.getString("workspace"));owned.mkdirs();File outside=new File(scratch,"outside");outside.mkdirs();File secret=new File(outside,"keep.txt");write(secret,"not followed");android.system.Os.symlink(outside.getPath(),new File(owned,"link").getPath());write(new File(owned,"own.txt"),"remove");deleted=reload.deleteProject(bid,true);check(deleted.getInt("deleted")==1&&!owned.exists(),"delete owned project files");check(secret.isFile(),"project deletion does not traverse symlink");
            ArrayList<String> all=new ArrayList<>();JSONArray ps=reload.projects();for(int i=0;i<ps.length();i++)all.add(ps.getJSONObject(i).getString("id"));check(reload.deleteProjects(all,false).getInt("deleted")==all.size(),"select-all project deletion");check(reload.projects().length()==1&&reload.currentChat()!=null,"empty library remains usable");
            File badDir=new File(scratch,"invalid");badDir.mkdirs();File bad=new File(badDir,"projects.json");write(bad,"{invalid");ProjectStore corrupt=new ProjectStore(badDir,new File(scratch,"bad-workspace"));check(!corrupt.lastError().isEmpty()&&corrupt.createProject("blocked")==null,"invalid index is read-only");check(read(bad).equals("{invalid"),"invalid original remains untouched");
            boolean failedClosed=false;try{corrupt.fileExclusions(new File(scratch,"bad-workspace").getPath());}catch(Exception expected){failedClosed=true;}check(failedClosed,"corrupt registry cannot drop file fences");
            localizedNames(new File(scratch,"localized-names"));
            legacyFileFence(new File(scratch,"legacy-fence"));
            return new JSONObject().put("project_checks",checks).put("scratch_only",true).put("api_level",android.os.Build.VERSION.SDK_INT);
        }finally{remove(scratch);}
    }
    private static void localizedNames(File scratch)throws Exception{
        String[][] labels={{"默认项目","新对话","项目 {number}","新对话 {number}"},{"Default project","New chat","Project {number}","New chat {number}"},{"デフォルトのプロジェクト","新しいチャット","プロジェクト {number}","新しいチャット {number}"},{"Proyecto predeterminado","Nueva conversación","Proyecto {number}","Nueva conversación {number}"},{"Projet par défaut","Nouvelle conversation","Projet {number}","Nouvelle conversation {number}"}};
        String[] keys={"默认项目","新对话","项目 {number}","新对话 {number}"};
        for(int language=0;language<labels.length;language++){
            final int[] selected={language};ProjectStore.NameTranslator translate=source->{for(int i=0;i<keys.length;i++)if(keys[i].equals(source))return labels[selected[0]][i];return source;};
            File files=new File(scratch,"language-"+language);ProjectStore store=new ProjectStore(files,new File(files,"work"),translate);
            check(store.currentProject().getString("name").equals(labels[language][0])&&store.currentChat().getString("title").equals(labels[language][1]),"localized initial project/chat "+language);
            store.createProject("  ");check(store.currentProject().getString("name").equals(labels[language][2].replace("{number}","2")),"localized unnamed project "+language);
            String original=store.currentChat().getString("title");JSONObject chat=store.createChat();check(chat.getString("title").equals(labels[language][3].replace("{number}","2")),"localized numbered chat "+language);
            selected[0]=(language+1)%labels.length;store.createChat();check(store.currentChat().getString("title").equals(labels[selected[0]][3].replace("{number}","3"))&&store.currentProject().getJSONArray("chats").getJSONObject(0).getString("title").equals(original),"language changes affect only future names "+language);
            JSONArray history=new JSONArray().put(new JSONObject().put("role","user").put("content","first message"));store.saveCurrent(history,"");check(store.currentChat().getString("title").equals("first message"),"localized placeholder still gets first message title "+language);
            String id=store.currentChat().getString("id");store.renameChat(id,labels[language][1]);store.saveCurrent(history,"");check(store.currentChat().getString("title").equals(labels[language][1]),"manual placeholder-like title preserved "+language);
            ProjectStore reload=new ProjectStore(files,new File(files,"work"),translate);check(reload.currentChat().getString("title").equals(labels[language][1])&&new JSONObject(read(new File(files,"projects.json"))).getJSONArray("projects").length()==2,"localized names persist "+language);
        }
    }
    private static void legacyFileFence(File scratch)throws Exception{
        File files=new File(scratch,"app"),root=new File(scratch,"workspace");files.mkdirs();root.mkdirs();String id=UUID.randomUUID().toString(),chat=UUID.randomUUID().toString();
        JSONObject project=new JSONObject().put("id",id).put("name","旧默认项目").put("workspace",root.getAbsolutePath()).put("currentChatID",chat).put("chats",new JSONArray().put(new JSONObject().put("id",chat).put("title","旧对话").put("history",new JSONArray()).put("transcript","")));
        write(new File(files,"projects.json"),new JSONObject().put("projects",new JSONArray().put(project)).put("currentProjectID",id).put("currentChatID",chat).toString());
        ProjectStore legacy=new ProjectStore(files,root);check(legacy.currentProject().getString("workspace").equals(root.getAbsolutePath()),"legacy default workspace is not moved");
        JSONObject other=legacy.createProject("独立项目");File foreignRoot=new File(other.getString("workspace"));foreignRoot.mkdirs();File foreign=new File(foreignRoot,"foreign.txt"),local=new File(root,"own.txt");write(foreign,"other project");write(local,"own project");
        JSONArray excluded=legacy.fileExclusions(root.getPath());check(excluded.length()==1&&excluded.getString(0).equals(foreignRoot.getCanonicalPath()),"pinned legacy workspace uses registry despite UI selecting another project");
        check(legacy.fileExclusions(foreignRoot.getPath()).length()==0,"legacy ancestor does not block the child's own workspace");
        java.util.concurrent.atomic.AtomicBoolean stop=new java.util.concurrent.atomic.AtomicBoolean(false);String relative="Projects/"+other.getString("id");
        for(String name:new String[]{"read_file","write_file","list_directory"}){
            JSONObject arguments=new JSONObject().put("path",relative+(name.equals("list_directory")?"":"/foreign.txt")).put("content","must not write").put("file_exclusions",new JSONArray()).put("workspace",foreignRoot.getPath());
            JSONObject operation=legacy.scopedFileOperation(root.getPath(),name,arguments);
            check(operation.getString("workspace").equals(root.getPath())&&operation.getJSONArray("file_exclusions").length()==1,"argument spoof cannot change authoritative IPC fence: "+name);
            boolean rejected=false;try{PrivilegedOperations.validateFileRequest(operation);}catch(Exception expected){rejected=true;}check(rejected,"App pre-dispatch rejects other project: "+name);
            rejected=false;try{PrivilegedOperations.fileTool(root.getPath(),name,arguments,stop,operation.getJSONArray("file_exclusions"));}catch(Exception expected){rejected=true;}check(rejected,"executor rejects other project: "+name);
        }
        check(read(foreign).equals("other project"),"cross-project write leaves original unchanged");
        JSONObject readOwn=PrivilegedOperations.fileTool(root.getPath(),"read_file",new JSONObject().put("path","own.txt"),stop,excluded);check(readOwn.getString("content").equals("own project"),"legacy local read remains available");
        PrivilegedOperations.fileTool(root.getPath(),"write_file",new JSONObject().put("path","written.txt").put("content","local write"),stop,excluded);check(read(new File(root,"written.txt")).equals("local write"),"legacy local write remains available");
        JSONObject list=PrivilegedOperations.fileTool(root.getPath(),"list_directory",new JSONObject().put("path","."),stop,excluded);check(!hasEntry(list,"Projects")&&hasEntry(list,"own.txt"),"legacy listing hides branch into other projects");
        JSONObject oldExecutor=new JSONObject().put("entries",new JSONArray().put(new JSONObject().put("name","Projects").put("type","directory")).put(new JSONObject().put("name","own.txt").put("type","file")));
        check(!hasEntry(PrivilegedOperations.filterFileResult(root.getPath(),"list_directory",new JSONObject().put("path","."),excluded,oldExecutor),"Projects"),"App response fence filters older executor listing");
        JSONObject child=PrivilegedOperations.fileTool(foreignRoot.getPath(),"read_file",new JSONObject().put("path","foreign.txt"),stop,legacy.fileExclusions(foreignRoot.getPath()));check(child.getString("content").equals("other project"),"independent project can read its own file");
        android.system.Os.symlink(foreignRoot.getPath(),new File(root,"alias").getPath());boolean aliasRejected=false;try{PrivilegedOperations.fileTool(root.getPath(),"read_file",new JSONObject().put("path","alias/foreign.txt"),stop,excluded);}catch(Exception expected){aliasRejected=true;}check(aliasRejected,"symlink ancestor cannot bypass other-project fence");
        boolean escaped=false;try{PrivilegedOperations.fileTool(root.getPath(),"write_file",new JSONObject().put("path","../escape.txt").put("content","blocked"),stop,excluded);}catch(Exception expected){escaped=true;}check(escaped&&!new File(scratch,"escape.txt").exists(),"parent traversal guard remains intact");
        JSONObject removed=legacy.deleteProject(id,true);check(removed.getInt("deleted")==1&&removed.getJSONArray("file_errors").length()==1&&local.isFile()&&foreign.isFile(),"legacy shared parent is still never deleted or relocated");
    }
    private static boolean hasEntry(JSONObject list,String name)throws Exception{JSONArray entries=list.getJSONArray("entries");for(int i=0;i<entries.length();i++)if(entries.getJSONObject(i).getString("name").equals(name))return true;return false;}
    private static void write(File f,String value)throws Exception{try(FileOutputStream out=new FileOutputStream(f)){out.write(value.getBytes(StandardCharsets.UTF_8));}}
    private static String read(File f)throws Exception{try(InputStream in=new FileInputStream(f);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1)out.write(b,0,n);return new String(out.toByteArray(),StandardCharsets.UTF_8);}}
    private static void remove(File f){try{File lexical=new File(f.getParentFile().getCanonicalFile(),f.getName());if(!f.getCanonicalFile().equals(lexical)){f.delete();return;}if(f.isDirectory()){File[] children=f.listFiles();if(children!=null)for(File c:children)remove(c);}f.delete();}catch(Exception ignored){}}
}
