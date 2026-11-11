#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/ttycom.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <termios.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
int main(int argc,char **argv) {
    if(argc!=3)return 2;
    write(2,"AgentGo terminal\r\n",18);
    signal(SIGTTOU,SIG_IGN);signal(SIGTTIN,SIG_IGN);
    if(setsid()<0){dprintf(2,"setsid: %s\n",strerror(errno));return 126;}
    write(2,"session ready\n",14);
    if(ioctl(0,TIOCSCTTY,0)<0){dprintf(2,"tty: %s\n",strerror(errno));return 126;}
    write(2,"tty ready\n",10);
    signal(SIGTTOU,SIG_IGN);
    if(tcsetpgrp(0,getpgrp())<0){dprintf(2,"foreground tty: %s\n",strerror(errno));return 126;}
    write(2,"foreground ready\n",17);
    sigset_t mask;sigemptyset(&mask);sigprocmask(SIG_SETMASK,&mask,NULL);
    int signals[]={SIGINT,SIGQUIT,SIGTSTP,SIGTTIN,SIGTTOU,SIGCHLD,SIGPIPE,SIGHUP,SIGTERM};for(unsigned i=0;i<sizeof(signals)/sizeof(signals[0]);i++)signal(signals[i],SIG_DFL);
    if(chdir(argv[1])){dprintf(2,"cwd: %s\n",strerror(errno));return 126;}
    write(2,"shell exec\n",11);
    const char *name=strrchr(argv[2],'/');name=name?name+1:argv[2];
    char *bash[]={argv[2],"--noprofile","--norc","-i",NULL};char *zsh[]={argv[2],"-f","-i",NULL};char *generic[]={argv[2],"-i",NULL};
    pid_t child=0;int error=posix_spawn(&child,argv[2],NULL,NULL,strcmp(name,"bash")==0?bash:strcmp(name,"zsh")==0?zsh:generic,environ);
    if(error){dprintf(2,"shell: %s\n",strerror(error));return 127;}
    int status=0;while(waitpid(child,&status,0)<0&&errno==EINTR){}return WIFEXITED(status)?WEXITSTATUS(status):128;
}
