\def\False{{\tt False}}
\def\Unsorted{{\tt Unsorted}}
\def\True{{\tt True}}
\def\VisualIDMask{{\tt VisualIDMask}}
\def\VisualScreenMask{{\tt VisualScreenMask}}
\def\VisualDepthMask{{\tt VisualDepthMask}}
\def\GCForeground{{\tt GCForeground}}
\def\GCBackground{{\tt GCBackground}}
\def\GCFont{{\tt GCFont}}
\def\GCGraphicsExposures{{\tt GCGraphicsExposures}}
\def\GCJoinStyle{{\tt GCJoinStyle}}
\def\JoinMiter{{\tt JoinMiter}}
\def\Button1MotionMask{{\tt Button1MotionMask}}
\def\ButtonPressMask{{\tt ButtonPressMask}}
\def\ButtonReleaseMask{{\tt ButtonReleaseMask}}
\def\ExposureMask{{\tt ExposureMask}}
\def\ButtonPress{{\tt ButtonPress}}
\def\ButtonRelease{{\tt ButtonRelease}}
\def\MotionNotify{{\tt MotionNotify}}
\def\Expose{{\tt Expose}}
\def\InputOutput{{\tt InputOutput}}
\def\CWBackPixel{{\tt CWBackPixel}}
@*Introduction. I want to write a program for a newsletter creator.  This
program will allow me to move news around, much like Microsoft Word.  But the
underlying format will be \.{DVI}, rather than Word.  This will allow me to
have the stability of \TeX{} without having to deal with \TeX's rigid
assumptions about how text should go.
@s stat int
@s dvi_txt_node int
@s box_list int
@s XEvent int
@s XRectangle int
@c
@h
@<Header inclusions@>@;
@<Global structure definitions@>@;
@<Global variable declarations@>@;
@<Global function declarations@>@;
@ @c int main(int argc,char*argv[])
{
    char* configfilename,*input_txt_name,*output_txt_name;
    struct defined_font* fnt_nxt;
    int ii,inputfd,configfd,xnum;
    char* configbuf,*configbufend;
    FILE* configfileout,*out_dvi_txt_file;
    struct stat configstat,inputstat;
    char* inputbuf,*inputbufend,move_buf[24];
    char*curr,*end_of_line,*name;
    struct dvi_txt_node**dvi_txt_arr,*dvi_tail,*dvi_head,*dvi_node,*dvi_nxt;
    struct box_list* boxn,*boxm;
    char*config_line;
    unsigned char*p;
    int text_width,text_x,text_y,quit_y,len;	
    XEvent xevent;

    @<Initialize the program@>@;
    @<Parse the command line@>@;
    @<Read the TFM database@>@;
    @<Read the config file, if it exists@>@; 
    @<Start up the X connection@>@;
    @<Read the \.{DVI} file, which should already be in \.{TXT} format@>@;
    @<Set the quit box@>@;
    XMapWindow(display,window);
    for(;;)
        @<Handle events@>@;
    @<Write out config file@>@;
    @<Write out new \.{DVI} file@>@;
    @<Clean up after ourselves@>@;
    return 0;
}
@ We will want to have strings, and X.
@<Header inclusions@>=
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
@*2Lists of DVI instructions. Here we will want lists and structs
@<Global structure definitions@>=
struct dvi_txt_node {
    struct dvi_txt_node*prev;
    struct dvi_txt_node*next;
    char*data;
    unsigned char*compiled_data;
    int clen; /* Length of compiled data */
};
@ We have some utility functions for modifying lists.
@<Global func...@>=
struct dvi_txt_node* allocate_dvi_txt_node(char* data);
void append_dvi_txt_node(struct dvi_txt_node**parent,
        struct dvi_txt_node*child);
void insert_dvi_txt_node(struct dvi_txt_node**parent,
        struct dvi_txt_node*child);
void destroy_dvi_txt_node(struct dvi_txt_node*dtm);
void remove_dvi_txt_node(struct dvi_txt_node*dtm);
@ @c
struct dvi_txt_node* allocate_dvi_txt_node(char* data)
{
    struct dvi_txt_node*ret;
    ret=(struct dvi_txt_node*)malloc(sizeof(struct dvi_txt_node));
    if(ret != (struct dvi_txt_node*)0){
        ret->data=copy_string(data); 
        ret->compiled_data=compile_string(data,&ret->clen);
        ret->next=ret->prev=(struct dvi_txt_node*)0;
    }
    return ret;
}
@ @<Global func...@>=
unsigned char* compile_string(const char* data,int*len);
unsigned char hex2byte(const char* p);
@ @c
unsigned char* compile_string(const char* data,int*len)
{
    const char* p;
    unsigned char* q,*s,*ret;
    p=data;
    s=q=(unsigned char*)malloc(1+strlen(data));
    for(;;){
        while(*p == ' ') 
            ++p;
        if(*p == '%')
            break;
        *q++ = hex2byte(p);
        p += 2;
    }
    ret=(unsigned char*)malloc(q-s);
    memcpy(ret,s,q-s);
    *len=q-s;
    free(s);
    return ret;
}
@ @c
unsigned char hex2byte(const char*p)
{
    char ret;

    ret = 0x0;
    @<Convert the hex to binary@>@;
    ++p;
    ret<<=4;
    @<Convert the hex to binary@>@;
    return ret;
}
@ @<Convert the hex to...@>=
switch(*p){
    case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9':
        ret |= *p - '0';@+break;
    case 'a': case 'b': case 'c':
    case 'd': case 'e': case 'f':
        ret |= *p - 'a' + 0xa;@+break;
}

@ @c
void destroy_dvi_txt_node(struct dvi_txt_node*dtm)
{
    free(dtm->data);
    free(dtm->compiled_data);
    memset(dtm,0x0,sizeof(struct dvi_txt_node));
    free(dtm);    
}
@ We just want to remove a node from the list, not destroy it.
@c
void remove_dvi_txt_node(struct dvi_txt_node*dtm)
{
    if(dtm->prev) 
        dtm->prev->next = dtm->next; 
    if(dtm->next)
        dtm->next->prev = dtm->prev;
}
@ @c
void append_dvi_txt_node(struct dvi_txt_node**parent,
        struct dvi_txt_node*child)
{
    struct dvi_txt_node*tmp;
    tmp=(struct dvi_txt_node*)0;
    if(parent && *parent)
        tmp=(*parent)->next;
    if(tmp !=(struct dvi_txt_node*)0)
        tmp->prev=child;
    child->next=tmp;
    if(parent && *parent)
        (*parent)->next=child;
    if(parent){
        child->prev=*parent;
        *parent=child;
    }@+else
        child->prev=(struct dvi_txt_node*)0;
}
@ @c
void insert_dvi_txt_node(struct dvi_txt_node**parent,
        struct dvi_txt_node*child)
{
    struct dvi_txt_node*tmp;
    tmp=(*parent)->prev;
    if(tmp !=(struct dvi_txt_node*)0)
        tmp->next = child;
    child->prev=tmp;
    (*parent)->prev=child;
    child->next=*parent;
    *parent=child; /* In case we are modifying the root of the list */
}
@*2Lists to handle boxes.
@<Global structure definitions@>=
struct box_list {
    struct box_list* next;
    struct dvi_txt_node* node;  
    char* name;
    int x;
    int y;
    int bwidth;
    int bheight;
    int pix_x;
    int pix_y;
    int pix_width;
    int pix_ht;
    int text_top;
    int text_bot;
    int moved;
    Pixmap pixmap;	
};
@ @<Global func...@>=
void destroy_box_list(struct box_list*bx);
struct box_list* allocate_box_list(char* name);
@ @c
struct box_list* allocate_box_list(char* name)
{
    struct box_list*ret;

    ret=(struct box_list*)malloc(sizeof(struct box_list));
    if(ret !=(struct box_list*)0){
        ret->name=copy_string(name);
        ret->next=(struct box_list*)0;
        ret->x=ret->y=ret->bwidth=ret->bheight=0;
    }
    return ret;
}
@ @c
void destroy_box_list(struct box_list*bx)
{
    XFreePixmap(display,bx->pixmap);
    free(bx->name);
    free(bx);
}
@ @<Global variable declarations@>=
struct box_list* the_boxes;
int num_dvi_lines;
@ @<Clean up...@>=
for(boxn=the_boxes;boxn;boxn=boxm){
    boxm=boxn->next;
    destroy_box_list(boxn);
}
@ @<Initialize the program@>=
the_boxes=(struct box_list*)0;
@*2Understanding the command line. Get the config file name, the input name,
the output name.
@d DEFAULT_PAGE_HT 643
@d DEFAULT_PAGE_WD 476
@<Parse the command line@>=
configfilename=input_txt_name=output_txt_name=(char*)0;
page_wd = DEFAULT_PAGE_WD;
page_ht = DEFAULT_PAGE_HT;
for(ii=1;ii<argc;++ii){
    @<Handle each command-line flag@>@; 
}
@ @<Handle each command-line flag@>=
    if(strcmp("-c",argv[ii])==0){
        ++ii;
        configfilename=argv[ii]; 
    }
@ @<Handle each command-line flag@>=
    if(strcmp("-i",argv[ii])==0){
        ++ii;
        input_txt_name = argv[ii];
    }
@ @<Handle each command-line flag@>=
    if(strcmp("-o",argv[ii])==0){
        ++ii;
        output_txt_name=argv[ii];
    }
@ @<Handle each command-line flag@>=
    if(strcmp("-t",argv[ii])==0){
        ++ii;
        tfm_db_file_name=argv[ii];
    }
@ This is a hint to give to X for displaying the page.  The default is
A4 letter size.
@<Handle each command-line flag@>=
    if(strcmp("-h",argv[ii])==0){
        ++ii;
        page_ht = atoi(argv[ii]); 
    }
@ @<Handle each command-line flag@>=
    if(strcmp("-w",argv[ii])==0){
        ++ii;
        page_wd = atoi(argv[ii])+6;            
    }
@ @<Parse the command line@>=
if(configfilename == (char*)0 ||
        input_txt_name == (char*)0 ||
        output_txt_name == (char*)0) 
    @<Print a helpful message@>@;
@ @<Global vari...@>=
int page_wd,page_ht;
@ @<Parse the command line@>=
out_dvi_txt_file=fopen(output_txt_name,"w");
if(out_dvi_txt_file == (FILE*)0){
    fprintf(stderr,"Could not open file \"%s\".\n",output_txt_name);
    _exit(0);
}
@ @<Clean up...@>=
fclose(out_dvi_txt_file);
@ @<Print a help...@>={
    fprintf(stderr,"Usage: %s <-c config> <-i input> <-o output>"
            " [-h page-height]\n\t[-w page-width]\t[-t tfm_db]\n\n",
            argv[0]);
    fprintf(stderr,"Default page height is 643pt and default page width"
            " is 470pt.\nThe dimensions are in points.\n\n");
    fprintf(stderr,"The format of the config file is in lines, with each line"
            " having the format:\n\t"
            "\"Name of box\" <horizontal offset> <vertical offset> <width> "
            "<height>\n\nThese dimensions are in sp.\n");
    _exit(0);
}
@*2Reading the config file. Use |stat| to check the file exists; If it does
exist, read it into memory.
Then close it and reopen it for writing.  Remember the |O_TRUNC| flag.
@<Read the config file, if it exists@>= 
configbuf=(char*)0;
if(stat(configfilename,&configstat) != 0) {
    if(errno != ENOENT){
        fprintf(stderr,"The file seems to exist, but there is "
               "another problem.  Errno is %d.\n",errno); 
        fprintf(stderr,"Please resolve the problem and try again.\n");
        _exit(0);
    }
}@+else{
    @<Read the config file into memory@>@;
}
@<Open the config file for writing@>@;
@ @<Read the config file into...@>=
configfd=open(configfilename,O_RDONLY);
if(configfd<0){
    fprintf(stderr,"Could not open \"%s\" for writing.\n",configfilename);
    _exit(0);
}
@ @<Read the config file into...@>=
configbuf=(char*)malloc(configstat.st_size);
read(configfd,configbuf,configstat.st_size);
close(configfd);
configbufend=configbuf + configstat.st_size;
@*2Reading the DVI file. The \.{DVI} file should have already been run through
\.{dvitotxt}.  We will work on the text output, which is basically assembler
for \.{DVI}.  We will have a linked list, which will be used for I/O.  An array
will be used for quick access. \.{txttodvi} will need to be modified to handle
the stack and number of pages.
@<Read the \.{DVI} file, which should already be in \.{TXT} format@>=
inputfd=open(input_txt_name,O_RDONLY);
if(inputfd<0){
    fprintf(stderr,"Could not get the file \"%s\" for reading.\n",
            input_txt_name);
    _exit(0);
}
fstat(inputfd,&inputstat);
inputbuf=(char*)malloc(inputstat.st_size);
read(inputfd,inputbuf,inputstat.st_size);
@ Now let us count the number of lines in the file.
@<Read the \.{DVI} file, which should already be in \.{TXT} format@>=
inputbufend=inputbuf+inputstat.st_size;
num_dvi_lines=0;
for(curr=inputbuf;curr<inputbufend;++curr)
    if(*curr == '\n')
        ++num_dvi_lines; 
@ Now we can create the list of nodes.
@<Read the \.{DVI} file, which should already be in \.{TXT} format@>=
dvi_txt_arr=(struct dvi_txt_node**)
    malloc(num_dvi_lines*sizeof(struct dvi_txt_node*));
curr=inputbuf;
end_of_line=inputbuf;
dvi_tail=(struct dvi_txt_node*)0;
for(ii=0;ii<num_dvi_lines;++ii){
    dvi_txt_arr[ii]=allocate_dvi_txt_node(get_line(curr,&end_of_line));
    append_dvi_txt_node(&dvi_tail,dvi_txt_arr[ii]);
    curr=end_of_line;
}
@ We should recognize that the \.{pre} and \.{post\_post} nodes will
never disappear; they will always be first and last, respectively. Thus we 
do not need to worry about a \.{bop} node being first or an \.{eop} node
being last. We insert a push immediately after the first \.{bop}.

The opcode \.{8b} represents a beginning-of-page.
@<Read the \.{D...@>=
dvi_head=dvi_txt_arr[0];
dvi_tail=dvi_txt_arr[num_dvi_lines-1];
@<Find the stack depth@>@;
@<Find all the boxes@>@;
for(dvi_node=dvi_head;dvi_node;dvi_node=dvi_node->next)
    if(prefix_matches(dvi_node->data,"8b ")){
        append_push(dvi_node);
        dvi_node=dvi_node->next;
        break; 
    }
@ @<Clean up...@>=
close(inputfd);
free(inputbuf);
free(dvi_txt_arr);
for(dvi_node=dvi_head;dvi_node;dvi_node=dvi_nxt){
    dvi_nxt=dvi_node->next;
    destroy_dvi_txt_node(dvi_node);
}
@ Now we replace all the rest of the \.{bop} nodes with
\.{push} nodes.
@<Read the \.{D...@>=
while(dvi_node){
    if(prefix_matches(dvi_node->data,"8b ")){
        append_push(dvi_node); 
        dvi_node=dvi_node->next;
        dvi_nxt=dvi_node->prev;
        remove_dvi_txt_node(dvi_nxt);
        destroy_dvi_txt_node(dvi_nxt);
    }
    dvi_node=dvi_node->next;
}
@ After this, there will be only one page in the document. We insert a pop
just before the last \.{eop} node. The opcode \.{8c} represents end-of-page.
@<Read the \.{D...@>=
for(dvi_node=dvi_tail;dvi_node;dvi_node=dvi_node->prev)
    if(prefix_matches(dvi_node->data,"8c ")){
        insert_pop(dvi_node);
        dvi_node=dvi_node->prev;
        break; 
    }
@ We replace all the rest of the \.{eop} nodes with \.{pop} nodes.
@<Read the \.{D...@>=
while(dvi_node){
    if(prefix_matches(dvi_node->data,"8c ")){
        insert_pop(dvi_node); 
        dvi_node=dvi_node->prev;
        dvi_nxt=dvi_node->next;
        remove_dvi_txt_node(dvi_nxt);
        destroy_dvi_txt_node(dvi_nxt);
    }
    dvi_node=dvi_node->prev;
}
@ @<Global funct...@>=
void append_push(struct dvi_txt_node*p);
void insert_pop(struct dvi_txt_node*p);
@ @c
void append_push(struct dvi_txt_node*p)
{
    struct dvi_txt_node*q;
    q=allocate_dvi_txt_node("8d %%");
    append_dvi_txt_node(&p,q);
}
@ @c
void insert_pop(struct dvi_txt_node*p)
{
    struct dvi_txt_node*q;
    q=allocate_dvi_txt_node("8e %%");
    insert_dvi_txt_node(&p,q);
}
@ Now we want to get the nodes that delimit the boxes. These are the \.{bop}
nodes at this point. Note that the boxes are retrieved from the DVI file,
and not from the config file.  So, if a user drops a box from the DVI file,
it will be eliminated in the config file that results from this run.
@^Only boxes in DVI file are output@>
@<Find all the boxes@>=
for(ii=0;ii<num_dvi_lines;++ii)
    if((name=string_contains(dvi_txt_arr[ii]->data,"newsdesc ")) != (char*)0){
        while(*name != ' ')
            ++name;
        ++name;
        boxn=allocate_box_list(remove_quotes(name));
        boxn->next=the_boxes;
        the_boxes=boxn;
    }
@ Now find the dimensions of each box.
@<Find all the boxes@>=
for(ii=0;ii<num_dvi_lines;++ii)
    if((name=string_contains(dvi_txt_arr[ii]->data,"newsdescbounds "))
            != (char*)0) {
        @<Find the box with the name@>@;
        @<Pull out the box dimensions and put them in the structure@>@; 
    }
@ We have some fussiness here.  We will be moving our boxes around.
We will want to insert moves just after the \.{push} node that corresponds
to the beginning of a page. We insert moves in |@<Write out new...@>|.
The description can have spaces, since the name is in the config file.
@^Box names can have spaces@>
@<Find the box with...@>=
while(*name != ' ')
    ++name;
++name;
for(boxn=the_boxes;boxn;boxn=boxn->next)
    if(prefix_matches(name,boxn->name)) {
        boxn->node=dvi_txt_arr[ii];
        while(!prefix_matches(boxn->node->data,"8b "))
            boxn->node=boxn->node->prev;
        boxn->node=boxn->node->next;
        break;
    }
@ Here we get the height and width of the box.  Note that we read it from the
DVI file, and not from the config file.  The idea is that the user can change
the \TeX{} document, which may change the size of the box.  But this does not
affect where we put the box. Thus the placement will still be the same, and the
user can tweak it as needed.

If the user creates a name with a colon-space, we will have a problem. Also,
if the user has digits in the name, we might have a problem.
@^Dimensions come from DVI@>
@^Names should not include colons@>
@^Names should not have digits@>
@<Pull out the box dimensions and put them in the structure@>=
if((name=string_contains(name,": ")) == (char*)0){
    fprintf(stderr,"Putative dimension string does not have a colon.\n");
    _exit(1);
}
if(boxn != (struct box_list*)0){
    boxn->bheight = get_integer(&name);
    boxn->bwidth = get_integer(&name);
    boxn->pix_width=(boxn->bwidth+65535)/65536;
    boxn->pix_ht=(boxn->bheight+65535)/65536;
    boxn->pixmap=XCreatePixmap(display,window,boxn->pix_width,
            boxn->pix_ht,1);
    @<Draw character boxes in our new pixmap@>@;
}
@ @<Draw character bo...@>=
dvi_node = boxn->node;
fix_state();
xgcvalues.function=GXclear;
XChangeGC(display,box_gc,GCFunction,&xgcvalues);
XFillRectangle(display,boxn->pixmap,box_gc,0,0,boxn->pix_width,boxn->pix_ht);
xgcvalues.function=GXset;
XChangeGC(display,box_gc,GCFunction,&xgcvalues);
while(!prefix_matches(dvi_node->data,"8c ")) {
    handle_dvi_command(dvi_node->compiled_data,dvi_node->clen,boxn->pixmap,
            box_gc,current_font);
    dvi_node=dvi_node->next;
}
if(check_state()){
    fprintf(stderr,"State has a bit of a problem.\n");
    _exit(0);
}
@ @<Find the stack...@>=
for(dvi_node=dvi_tail;dvi_node;dvi_node=dvi_node->prev)
    if(*dvi_node->compiled_data == post){
        fprintf(stderr,"%s\n",dvi_node->data);
        max_stack_depth=get_unsigned_int(&dvi_node->compiled_data[25],2); 
        fprintf(stderr,"%02x %02x\n",
                dvi_node->compiled_data[25],
                dvi_node->compiled_data[26]);
        max_stack_depth += 3;
        fprintf(stderr,"max_stack_depth is %d.\n",max_stack_depth);
        break;
    }
dvi_stack=(struct dvi_params*)malloc(max_stack_depth*sizeof(struct dvi_params));
@ @<Global vari...@>=
unsigned int max_stack_depth;
@ @<Global func...@>=
void fix_state(void);
int check_state(void);
void push_state(void);
void pop_state(void);
@ We are starting a page, so initialize the DVI parameters: set the stack
pointer to 0, current font to undefined, and zero out the current dvi
parameters.
@c
void fix_state(void)
{
    dvi_sp=0;
    memset(&dvi_stack[0],0,sizeof(struct dvi_params));
    current_font=(struct defined_font*)0;
}
@ @c
void push_state(void)
{
    memcpy(&dvi_stack[dvi_sp+1],&dvi_stack[dvi_sp],
            sizeof(struct dvi_params));
    ++dvi_sp;
    if(dvi_sp >= max_stack_depth){
        fprintf(stderr,"Attempted stack overflow?\n"); 
        _exit(0);
    }
}
@ @c
void pop_state(void)
{
    --dvi_sp;
}
@ @<Global struc...@>=
struct dvi_params {
    int h,v,w,x,y,z;
};
@ @<Global vari...@>=
struct dvi_params* dvi_stack;
struct defined_font* current_font;
int dvi_sp;
@ @c
int check_state(void)
{
   return dvi_sp; 
}
@ @<Clean up...@>=
free(dvi_stack);
@ Now, if there was a config file, we want to get the offsets from it.
@<Find all the boxes@>=
if(configbuf != (char*)0) {
    curr = configbuf;
    while(curr < configbufend){
        config_line=get_line(curr,&end_of_line);
        name=get_name_from_line(&config_line);
        @<Scan the list of boxes to find a match@>@;
        curr=end_of_line; 
    }
}
@ @<Scan the list of box...@>=
for(boxn=the_boxes;boxn;boxn=boxn->next)
    if(strcmp(boxn->name,name)==0){
        boxn->x=get_integer(&config_line);
        boxn->y=get_integer(&config_line); 
        boxn->pix_x=(boxn->x+65535)/65536;
        boxn->pix_y=(boxn->y+65535)/65536;
        break;
    }
@ @<Open the conf...@>=
if((configfileout=fopen(configfilename,"w")) == (FILE*)0) {
    fprintf(stderr,"Could not open \"%s\" for writing.\n",configfilename);
    _exit(0);
}
@ @<Clean up...@>=
fclose(configfileout);
@*2Writing the files. The config file will be a text file.  The idea is that
the user can manually adjust it with fine-tuning, then run our program to write
out the DVI.
@<Write out config file@>=
for(boxn=the_boxes;boxn;boxn=boxn->next)
    fprintf(configfileout,"\"%s\" %d %d %d %d\n",boxn->name,boxn->x,boxn->y,
		boxn->bwidth,boxn->bheight);    
@ We insert our moves. The \.{92} is the opcode for a four-byte move to the
right, and \.{a0} is the opcode for a four-byte move down.
@<Write out new \.{DVI} file@>=
for(boxn=the_boxes;boxn;boxn=boxn->next){
    if(boxn->x != 0){
        sprintf(move_buf,"92 %08x %%",boxn->x); 
        insert_dvi_txt_node(&boxn->node,allocate_dvi_txt_node(move_buf));
    }
    if(boxn->y != 0){
        sprintf(move_buf,"a0 %08x %%",boxn->y); 
        insert_dvi_txt_node(&boxn->node,allocate_dvi_txt_node(move_buf));
    }
}
@ Let us get rid of the specials.
@<Write out new \.{DVI} file@>=
for(dvi_node=dvi_head;dvi_node;dvi_node=dvi_nxt){
    dvi_nxt=dvi_node->next;
    if(string_contains(dvi_node->data,"newsdesc ") != (char*)0 ||
            string_contains(dvi_node->data,"newsdescbounds ") != (char*)0){
        remove_dvi_txt_node(dvi_node);
        destroy_dvi_txt_node(dvi_node);
    }
}
@ Finally, we can write out the \.{DVI} file in its glory.
@<Write out new \.{DVI} file@>=
for(dvi_node=dvi_head;dvi_node;dvi_node=dvi_node->next)
    fprintf(out_dvi_txt_file,"%s\n",dvi_node->data);
@*Graphical User Interface implementation. We will want to get the fonts.  We
will get a window, and some pixmaps.  One pixmap will handle the current window
state.  Another pixmap will handle the box as it is being shifted around.  A
list of boxes will be available on the right.  The user will click to identify
the box being used. The box being used will be hightlighted in red.  It will
need to be deleted from the ``stable'' pixmap.
@s Display int
@s Visual int
@s XVisualInfo int
@s Font int
@s XFontStruct int
@s XSetWindowAttributes int
@s Pixmap int
@s GC int
@s XGCValues int
@s Window int
@s XWindowAttributes int
@<Start up the X connection@>=
display=XOpenDisplay((char*)0);
if(display==(Display*)0){
    fprintf(stderr,"Could not get a display.\n");
    _exit(0);
}
screen_num=XDefaultScreen(display);
scr_ht=DisplayHeight(display,screen_num);
scr_wd=DisplayWidth(display,screen_num);
@ @<Global vari...@>=
Display *display;
int screen_num,scr_ht,scr_wd;
Visual*visual;
XVisualInfo xvinfo,*vinfo;
Font font;
XFontStruct* fonts;
int max_text_width;
XSetWindowAttributes xset;
Window window;
XWindowAttributes winatt;
GC our_gc,box_gc;
XGCValues xgcvalues;
Pixmap boxpixmap,tpm;
@ @<Header incl...@>=
#include <X11/Xlib.h>
#include <X11/X.h>
#include <X11/Xutil.h>
@ @<Clean up...@>=
@<Drop all the X stuff@>@;
XCloseDisplay(display);
@ Let us get some information about our screen.
@s VisualIDMask TeX
@s VisualScreenMask TeX
@s VisualDepthMask TeX
@<Start up the X connection@>=
if((visual=DefaultVisual(display,screen_num)) == (Visual*)0){
    fprintf(stderr,"Could not get a visual.\n");
    _exit(0);
}
xvinfo.visualid = XVisualIDFromVisual(visual);
xvinfo.screen=screen_num;
xvinfo.depth=DefaultDepth(display,screen_num);
vinfo=XGetVisualInfo(display,
    VisualIDMask|VisualScreenMask|VisualDepthMask,
    &xvinfo,
    &xnum); 
if(!vinfo){
   fprintf(stderr,"Could not get visual info.\n"); 
   _exit(0);
}
@ @<Drop all...@>=
XFree(vinfo);
@ Let us get a font. Then we compute the space we need on the right hand
side of the window.
@<Start up...@>=
font=XLoadFont(display,"7x13");
fonts=XQueryFont(display,font);
max_text_width=0;
for(boxn=the_boxes;boxn;boxn=boxn->next)
   if((text_width=XTextWidth(fonts,boxn->name,strlen(boxn->name))) >
           max_text_width)
       max_text_width = text_width;
if((text_width=XTextWidth(fonts,"Quit",4)) > max_text_width)
   max_text_width = text_width;
max_text_width += 10;   
@ @<Drop all...@>=
#if 0
XFreeFont(display,fonts);
XUnloadFont(display,font);
#endif
@ Now we are ready to create the window.
@s InputOutput TeX
@s CWBackPixel TeX
@<Start up...@>=
xset.background_pixel=WhitePixel(display,screen_num);
window=XCreateWindow(display,DefaultRootWindow(display),
        0,scr_ht/8,scr_wd/2,3*scr_ht/4,0,DefaultDepth(display,screen_num),
        InputOutput,visual,
        CWBackPixel,
        &xset);
@ If we want one pixel per point, the height will be 643 pixels and the width
will be 470 pixels for the default size.
@<Global func...@>=
void configure_window_attributes();
@ @c
void configure_window_attributes(void)
{
    XWindowAttributes twinatt;
    memcpy(&twinatt,&winatt,sizeof(XWindowAttributes));
    @<Get the window attributes current at the server@>@;
    if(twinatt.width != winatt.width || twinatt.height != winatt.height)
        @<Reset the GC's@>@;
}
@ @<Start up...@>=
@<Get the window attributes current at the server@>@;
@ @<Get the window attributes current at the server@>=
XGetWindowAttributes(display,window,&winatt);
if(winatt.width < max_text_width){
    fprintf(stderr,"Window is not wide enough.\n");
    _exit(0);
}
#if 0
fprintf(stderr,"The window size is %d X %d.\n",winatt.height,winatt.width);
#endif
@ @<Drop all...@>=
XDestroyWindow(display,window);
@ @<Set up |box...@>=
boxpixmap=XCreatePixmap(display,window,winatt.width,
    winatt.height,DefaultDepth(display,screen_num));
@ @<Start up...@>=
@<Set up |box...@>@;
@ @<Drop all...@>=
XFreePixmap(display,boxpixmap);
@ Now we are ready to get some GCs.
@s GCForeground TeX
@s GCBackground TeX
@s GCFont TeX
@s GCGraphicsExposures TeX
@s JoinMiter TeX
@<Start up...@>=
@<Set up GC's@>@;
@
@s False TeX
@<Set up GC's@>=
xgcvalues.foreground=BlackPixel(display,screen_num);
xgcvalues.background=WhitePixel(display,screen_num);
xgcvalues.font=font;
xgcvalues.graphics_exposures=False;
xgcvalues.join_style=JoinMiter;
our_gc=XCreateGC(display,boxpixmap,GCForeground|GCBackground|GCFont
        |GCGraphicsExposures|GCJoinStyle,&xgcvalues);
tpm=XCreatePixmap(display,window,winatt.width,winatt.height,1);
box_gc=XCreateGC(display,tpm,0,0);
XFreePixmap(display,tpm);
@
@s GCJoinStyle TeX
@s Unsorted TeX
@ @<Reset the GC's@>={
    XFreePixmap(display,boxpixmap);
    @<Set up |boxpixmap|@>@;
}
@ @<Drop all...@>=
XFreeGC(display,our_gc);
@ OK, let us map the window now, and start processing
events.
@s Button1MotionMask TeX
@s ButtonPressMask TeX
@s ButtonReleaseMask TeX
@s ExposureMask TeX
@s True TeX
@<Start up...@>=
XSelectInput(display, window,
        Button1MotionMask|ButtonPressMask|ButtonReleaseMask|ExposureMask);
@ @<Set the quit box@>=
text_x=min(winatt.width-max_text_width+5,page_wd);
text_y=fonts->max_bounds.ascent+3;
for(boxn=the_boxes;boxn;boxn=boxn->next){
    boxn->text_bot=text_y+1+fonts->max_bounds.descent;
    boxn->text_top=text_y-1-fonts->max_bounds.ascent;
    text_y += fonts->max_bounds.ascent+3+fonts->max_bounds.descent;
    fprintf(stderr,"text_y=%d\n",text_y);
}
quit_y = text_y - 1 - fonts->max_bounds.ascent;
fprintf(stderr,"quit_y=%d.\n",quit_y);
@ @<Global vari...@>=
int min(int x,int y)
{
    return (x>y)?y:x;	
}
@
@s ButtonPress TeX
@s ButtonRelease TeX
@s MotionNotify TeX
@s Expose TeX
@<Handle events@>={
    XNextEvent(display,&xevent); 
    switch(xevent.type){
        case ButtonPress:
            @<Check if user is selecting a new box or quitting@>@; 
            break;
        case ButtonRelease:
            @<If there is a current box, let it go@>@;
            break;
        case MotionNotify:
            @<Move the current box, if there is one@>@;
            break;
        case Expose:
            /* We should actually do some more here, about checking whether a 
               window has changed size and so on. */
            configure_window_attributes();
            redraw_window();
            break;
        default:
            break;
    }
}
finished_x:
@<Fix the units in the boxes@>@;
@ @<Fix the units in the boxes@>=
for(boxn=the_boxes;boxn;boxn=boxn->next)
    if(boxn->moved){
       boxn->x=boxn->pix_x*65536;
       boxn->y=boxn->pix_y*65536;  
    }
@ @<If there is a current box, let it go@>=
if(active_box && active_state==1)
    active_state=0;
else
    active_box=(struct box_list*)0;
redraw_window();
@ @<Move the current box, if there is one@>=
if(active_box && xevent.xmotion.x < text_x - 5){
    active_box->pix_x=xevent.xmotion.x;
    active_box->pix_y=xevent.xmotion.y;
    active_box->moved = 1;
    while(XCheckWindowEvent(display,window,Button1MotionMask,&xevent))
        if(active_box && xevent.xmotion.x < text_x - 5){
            active_box->pix_x=xevent.xmotion.x;
            active_box->pix_y=xevent.xmotion.y;
        } 
    redraw_window();
}
@ @<Check if user...@>=
    if(xevent.xbutton.x > text_x - 5){
        if(xevent.xbutton.y>quit_y){
            fprintf(stderr,"quit_y = %d. You click below it.\n",quit_y);
            goto finished_x;
        }
        for(boxn=the_boxes;boxn;boxn=boxn->next)
            if(xevent.xbutton.y>boxn->text_top &&
                    xevent.xbutton.y<boxn->text_bot) {
                if(!active_box){
                    active_box=boxn; 
                    active_state=1;
                    redraw_window();
                    break;
                }@+else{
                    active_box = (struct box_list*)0; 
                    redraw_window();
                }
            }
    }@+else
   @<Move current box to this point@>@;
@ @<Global vari...@>=
int active_state;
@ @<Initialize the pro...@>=
active_state=0;
@ @<Move current box to this point@>=
    if(active_box && xevent.xbutton.x < text_x - 5) {
        active_box->pix_x=xevent.xbutton.x;
        active_box->pix_y=xevent.xbutton.y;
        active_box->moved=1;
        redraw_window();
    }
@ @<Global func...@>=
void redraw_window(void);
@ @c
void redraw_window(void)
{
    struct box_list*boxn;
    int text_x,text_y;
    xgcvalues.clip_mask=None;
    xgcvalues.foreground=WhitePixel(display,screen_num); 
    XChangeGC(display,our_gc,GCForeground|GCClipMask,&xgcvalues);
    XFillRectangle(display,boxpixmap,our_gc,0,0,winatt.width+1,
            winatt.height+1);
    text_x=min(winatt.width-max_text_width+5,page_wd);
    text_y=fonts->max_bounds.ascent+3;
    @<Draw the boxes@>@;
    @<Clear the area for text@>@;
    xgcvalues.foreground=BlackPixel(display,screen_num); 
    XChangeGC(display,our_gc,GCForeground,&xgcvalues);
    XDrawLine(display,boxpixmap,our_gc,text_x-5,0,
            text_x-5,winatt.height);
    if(winatt.height>page_ht)
        XDrawLine(display,boxpixmap,our_gc,0,page_ht,text_x-5,page_ht);
    @<Draw the strings@>@;
    XCopyArea(display,boxpixmap,window,our_gc,0,0,winatt.width,
            winatt.height,0,0);
}
@ @<Draw the strings@>=
xgcvalues.foreground=BlackPixel(display,screen_num);
XChangeGC(display,our_gc,GCForeground,&xgcvalues);
for(boxn=the_boxes;boxn;boxn=boxn->next){
    XDrawString(display,boxpixmap,our_gc,text_x,text_y,boxn->name,
            strlen(boxn->name));
    text_y += fonts->max_bounds.ascent+3+fonts->max_bounds.descent;
}
XDrawString(display,boxpixmap,our_gc,text_x,text_y,"Quit",4);
@ @<Clear the area for text@>=
    xgcvalues.clip_mask=None;
    xgcvalues.foreground=WhitePixel(display,screen_num);
    XChangeGC(display,our_gc,GCForeground|GCClipMask,&xgcvalues);
    XFillRectangle(display,boxpixmap,our_gc,0,page_ht,winatt.width,
            winatt.height-page_ht);
    XFillRectangle(display,boxpixmap,our_gc,text_x-5,0,winatt.width-text_x+5,
            winatt.height);
@ @<Draw the boxes@>=
for(boxn=the_boxes;boxn;boxn=boxn->next){
    if(boxn != active_box) {
        xgcvalues.clip_mask=boxn->pixmap;
        xgcvalues.clip_x_origin=boxn->pix_x;
        xgcvalues.clip_y_origin=boxn->pix_y;
        xgcvalues.foreground=BlackPixel(display,screen_num);
        XChangeGC(display,our_gc,GCClipXOrigin|GCClipYOrigin|GCClipMask
                |GCForeground,&xgcvalues);
        XFillRectangle(display,boxpixmap,our_gc,boxn->pix_x,
                boxn->pix_y,boxn->pix_width,boxn->pix_ht); 
        xgcvalues.clip_mask=None;
        XChangeGC(display,our_gc,GCClipMask,&xgcvalues);
        XDrawRectangle(display,boxpixmap,our_gc,boxn->pix_x,
                boxn->pix_y,boxn->pix_width,boxn->pix_ht);
    }
}
@ @<Draw the boxes@>=
for(boxn=the_boxes;boxn;boxn=boxn->next){
    if(boxn == active_box){
        xgcvalues.clip_mask=boxn->pixmap;
        xgcvalues.clip_x_origin=boxn->pix_x;
        xgcvalues.clip_y_origin=boxn->pix_y;
        xgcvalues.foreground=vinfo[0].red_mask;
        XChangeGC(display,our_gc,GCClipXOrigin|GCClipYOrigin|GCClipMask
                |GCForeground,&xgcvalues);
        XFillRectangle(display,boxpixmap,our_gc,boxn->pix_x,
                boxn->pix_y,boxn->pix_width,boxn->pix_ht); 
        xgcvalues.clip_mask=None;
        XChangeGC(display,our_gc,GCClipMask,&xgcvalues);
        XDrawRectangle(display,boxpixmap,our_gc,boxn->pix_x,
                boxn->pix_y,boxn->pix_width,boxn->pix_ht);
    }
}
@ @<Initialize the pr...@>=
active_box=(struct box_list*)0;
@ @<Global vari...@>=
struct box_list*active_box;
@*Utilities. We need a few utilities.
@<Global func...@>=
int prefix_matches(char*s,char*pre);
char* string_contains(char*s,char*match);
char* copy_string(char*s);
char* get_line(char*beg,char**end);
int get_integer(char**name);
char* get_name_from_line(char**lin);
char* remove_quotes(char*p);
@ Check if |pre| is a prefix of |s|.
@c
int prefix_matches(char*s,char*pre)
{
    int ret;
    ret=0;
    while(*s && *pre){
        if(*s != *pre)
            break;
        ++s;
        ++pre;
    } 
    if(*pre == '\0') 
        ret = 1;
    return ret;
}
@ @c
char* string_contains(char*s,char*match)
{
    char*ret,*p;
    ret=(char*)0;
    for(p=s;*p;++p)
        if(*p == *match && prefix_matches(p,match)){
            ret=p;
            break; 
        }
    return ret;
}
@ @c
char* copy_string(char*s)
{
    char*ret;
    ret=(char*)malloc(sizeof(char)*(1+strlen(s)));
    if(ret != (char*)0)
        strcpy(ret,s); 
    return ret;
}
@ @c
char* get_line(char*beg,char**end)
{
    *end=beg;
    while(**end != '\n')
       ++*end;
    if(**end == '\n'){
        **end = '\0';
        ++*end;
    }
    return beg;
}
@ @c
int get_integer(char**name)
{
    int ret;
    ret = 0;
    while(name && *name && **name) {
        if(**name >= '0' && **name <= '9')
            break;
        ++*name;
    }
    while(name && *name && **name >= '0' && **name <= '9'){
        ret *= 10;
        ret += **name - '0'; 
        ++*name;
    }
    return ret;
}
@ @c
char* get_name_from_line(char**lin)
{
    char* ret,*p;
    ret = (char*)0;
    p=*lin;
    while(p && *p && *p != '"')
        ++p;
    if(*p == '"')
        ret = ++p;
    while(p && *p && *p != '"')
        ++p;
    if(*p == '"'){
        *p='\0';
        *lin = p+1;
    }
    return ret;
}
@ @c
char* remove_quotes(char*p)
{
    char*q,*s;
    s=q=p;
    while(*p){
        while(*p && *p == '"') 
            ++p;
        *q=*p;
        ++q;
        if(*p)
            ++p;
    }
    return s;
}
@**Font management. We learn how to load fonts. The first item of 
business is to have a list on which we keep the list of loaded fonts.
@<Global struct...@>=
struct defined_font {
    struct defined_font* next;
    unsigned int num,lf,lh,bc,ec,nw;
    unsigned int nh,nd,ni,nl,nk,ne,np;
    unsigned int*header,*char_info,*lig_kern,*exten;
    int*width,*height,*depth,*italic,*kern,*param;
};
@ @<Global vari...@>=
unsigned char font_name[512];
@ @<Global func...@>=
const char* get_hash(const char*);
@ @c
const char* get_hash(const char*name)
{
    int left, right, mid;
    fprintf(stderr,"num_tfm_lines is %d.\n",num_tfm_lines);
    fprintf(stderr,"looking for %s\n",name);
    left = 0;
    right = num_tfm_lines - 1;
    mid = (left+right)/2;
    while(left<=right) {
        fprintf(stderr,"looking at %s\n",tfm_database[mid].tex_name);
        mid = (left+right)/2;
        if(strcmp(tfm_database[mid].tex_name,name)>0)
            right = mid - 1;
        else if(strcmp(tfm_database[mid].tex_name,name)<0)
            left = mid + 1;
        else if(strcmp(tfm_database[mid].tex_name,name)==0)
            return tfm_database[mid].file_name;
    }
    fprintf(stderr,"Did not find %s.\n",name);
    fflush(stderr);
    _exit(1);
}
@ @<Global func...@>=
int get_width(struct defined_font*,unsigned int);
@ @c
int get_width(struct defined_font*p,unsigned int n)
{
    if(n<p->bc||n>p->ec)
        return 0;
    n -= p->bc;
    return p->width[(p->char_info[n]>>24)&0xff];
}
@ @<Global vari...@>=
struct defined_font*defined_font_list=0;
@ @<Clean up...@>=
while(defined_font_list){
    fnt_nxt = defined_font_list->next;  
    clean_up_font(defined_font_list);
    defined_font_list = fnt_nxt;
}
@ @<Global func...@>=
void clean_up_font(struct defined_font*);
@ @c
void clean_up_font(struct defined_font*p)
{
    if(p) {
        free(p->header);
        free(p->char_info);
        free(p->width);
        free(p->height);
        free(p->depth);
        free(p->italic);
        free(p->lig_kern);
        free(p->kern);
        free(p->exten);
        free(p->param);
        free(p);
    }
}
@ We read in a font.
@<Global func...@>=
struct defined_font* read_font_file(const char*);
@ @c
struct defined_font* read_font_file(const char*name)
{
    int len;
    struct defined_font*ret;
    unsigned char* buf = read_file(name,&len);
    int offset;
    int ii;
    ret=(struct defined_font*)malloc(sizeof(struct defined_font)); 
    if(!ret){
        fprintf(stderr,"Could not allocate memory for a font buffer.\n");
        fflush(stderr);
        _exit(1);
    }
    @<Get the first parameters@>@;
    @<Read the spacing data@>@;
    free(buf);
    return ret;
}
@ @<Get the first param...@>=
ret->lf=get_unsigned_int(&buf[0],2);
if(len != ret->lf * 4) {
    fprintf(stderr,"len = %d. ret->lf = %d.\n",len,ret->lf*4);
    fprintf(stderr,"This file might be corrupted.\n");
    fflush(stderr);
    _exit(1);
}
@ @<Get the first param...@>=
ret->lh=get_unsigned_int(&buf[2],2);
@ @<Get the first param...@>=
ret->bc=get_unsigned_int(&buf[4],2);
if(ret->bc > 256){
    fprintf(stderr,"ret->bc bigger than expected.\n");
    fprintf(stderr,"This file might be corrupted.\n");
    fflush(stderr);
    _exit(1);
}
@ @<Get the first param...@>=
ret->ec=get_unsigned_int(&buf[6],2);
if(ret->ec + 1 < ret->bc){
    fprintf(stderr,"ret->ec = %d, ret->bc = %d.\n",ret->ec,ret->bc);
    fprintf(stderr,"ret->ec smaller than expected.\n");
    fprintf(stderr,"This file might be corrupted.\n");
    fflush(stderr);
    _exit(1);
}
@ @<Get the first param...@>=
ret->nw=get_unsigned_int(&buf[8],2);
@ @<Get the first param...@>=
ret->nh=get_unsigned_int(&buf[10],2);
@ @<Get the first param...@>=
ret->nd=get_unsigned_int(&buf[12],2);
@ @<Get the first param...@>=
ret->ni=get_unsigned_int(&buf[14],2);
@ @<Get the first param...@>=
ret->nl=get_unsigned_int(&buf[16],2);
@ @<Get the first param...@>=
ret->nk=get_unsigned_int(&buf[18],2);
@ @<Get the first param...@>=
ret->ne=get_unsigned_int(&buf[20],2);
@ @<Get the first param...@>=
ret->np=get_unsigned_int(&buf[22],2);
@ @<Get the first param...@>=
if(ret->lf+ret->bc!=6+ret->lh+ret->ec+1+ret->nw+ret->nh+ret->nd+
    ret->ni+ret->nl+ret->nk+ret->ne+ret->np){
    fprintf(stderr,"This file might be corrupted.\n");
    fflush(stderr);
    _exit(1);
}
@ @<Read the spacing data@>= 
offset = 24;
@<Read the |header| information@>@;
@<Read the |char_info| information@>@;
@<Read the |width| information@>@;
@<Read the |height| information@>@;
@<Read the |depth| information@>@;
@<Read the |italic| information@>@;
@<Read the |lig_kern| information@>@;
@<Read the |kern| information@>@;
@<Read the |exten| information@>@;
@<Read the |param| information@>@;
@ @<Read the |header| information@>=
ret->header = (unsigned int*)malloc(sizeof(unsigned int)*ret->lh);
if(!ret->header){
    fprintf(stderr,"Could not get header information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->lh;++ii,offset += 4)
   ret->header[ii]=get_unsigned_int(&buf[offset],4);
@ @<Read the |char_info| information@>=
ret->char_info =
    (unsigned int*)malloc(sizeof(unsigned int)*(ret->ec-ret->bc+1));
if(!ret->char_info){
    fprintf(stderr,"Could not get char_info information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->ec-ret->bc+1;++ii,offset += 4)
   ret->char_info[ii]=get_unsigned_int(&buf[offset],4);
@ @<Read the |width| information@>=
ret->width=(int*)malloc(sizeof(int)*ret->nw);
if(!ret->width){
    fprintf(stderr,"Could not get width information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->nw;++ii,offset += 4)
   ret->width[ii]=buf_to_scaled_int(&buf[offset],ret->header[1]);
@ @<Global func...@>=
int buf_to_scaled_int(unsigned char*,int);
@ I got this function directly from the code for \TeX. See section 
572 in the \TeX{} web source.
@c int buf_to_scaled_int(unsigned char*p,int z)
{
    unsigned char a,b,c,d;
    int alpha,beta;
    int ret;
    a = p[0];@+b = p[1];@+c = p[2];@+d = p[3];
    alpha = 16;
    z >>=4;
    while(z > 0x800000){
        z /= 2;
        alpha *= 2;
    }
    beta = 256/alpha;@+alpha *= z; 
    ret = (d * z) / 0x100;@+ret += (c*z);@+ret /= 0x100;
    ret += b*z;@+ret /= beta;
    if(a == 0xff)
        ret -= alpha;
    return ret;
}
@ @<Read the |height| information@>=
ret->height=(int*)malloc(sizeof(int)*ret->nh);
if(!ret->height){
    fprintf(stderr,"Could not get height information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->nh;++ii,offset += 4)
   ret->height[ii]=get_int(&buf[offset],4);
@ @<Read the |depth| information@>=
ret->depth = (int*)malloc(sizeof(int)*ret->nd);
if(!ret->depth){
    fprintf(stderr,"Could not get depth information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->nd;++ii,offset += 4)
   ret->depth[ii]=get_int(&buf[offset],4);
@ @<Read the |italic| information@>=
ret->italic = (int*)malloc(sizeof(int)*ret->ni);
if(!ret->italic){
    fprintf(stderr,"Could not get italic information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->ni;++ii,offset += 4)
   ret->italic[ii]=get_int(&buf[offset],4);
@ @<Read the |lig_kern| information@>=
ret->lig_kern =
    (unsigned int*)malloc(sizeof(unsigned int)*ret->nl);
if(!ret->lig_kern){
    fprintf(stderr,"Could not get lig_kern information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->nl;++ii,offset += 4)
   ret->lig_kern[ii]=get_unsigned_int(&buf[offset],4);
@ @<Read the |kern| information@>=
ret->kern = (int*)malloc(sizeof(int)*ret->nk);
if(!ret->kern){
    fprintf(stderr,"Could not get kern information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->nk;++ii,offset += 4)
   ret->kern[ii]=get_int(&buf[offset],4);
@ @<Read the |exten| information@>=
ret->exten =
    (unsigned int*)malloc(sizeof(unsigned int)*ret->ne);
if(!ret->exten){
    fprintf(stderr,"Could not get exten information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=0;ii<ret->ne;++ii,offset += 4)
   ret->exten[ii]=get_unsigned_int(&buf[offset],4);
@ @<Read the |param| information@>=
ret->param = (int*)malloc(sizeof(int)*(ret->np+1));
if(!ret->param){
    fprintf(stderr,"Could not get param information about the font.\n");
    fflush(stderr);
    _exit(1);
}
for(ii=1;ii<=ret->np;++ii,offset += 4)
   ret->param[ii]=get_int(&buf[offset],4);
@ @<Global func...@>=
int matches(const char*,int,const char*);
int scan_for_integer(const char*,int,const char**);
@ @c
int scan_for_integer(const char*p,int n,const char**pc)
{
    int ii;    
    int ret=0;
    for(ii=0;ii<n && (p[ii]<'0' || p[ii]>'9');++ii);
    while(ii<n && p[ii]>='0' && p[ii]<='9'){
        ret *= 10; 
        ret += p[ii] - '0';
        ++ii;
    }
    if(pc)
        *pc = &p[ii];
    return ret;
}
@ @c
int matches(const char*data,int len,const char*s)
{
    int ii,jj,kk;
    for(ii=0;ii<len;++ii){
        kk = 0;
        for(jj=ii;jj<len;++jj){
            if(s[kk] == '\0')
                return 1; 
            else if(data[jj] != s[kk]) 
                break;       
            ++kk;
        } 
        if(jj==len && s[kk] == '\0')
            return 1;
    }
    return 0;
}
@*DVI opcodes. We need the DVI opcodes to decide what to do with the boxes.
@<Global struc...@>=
typedef enum {
    set_char_0 = 0, set_char_1, set_char_2, set_char_3,
    set_char_4, set_char_5, set_char_6, set_char_7,
    set_char_8, set_char_9, set_char_10, set_char_11,
    set_char_12, set_char_13, set_char_14, set_char_15,
    set_char_16, set_char_17, set_char_18, set_char_19,
    set_char_20, set_char_21, set_char_22, set_char_23,
    set_char_24, set_char_25, set_char_26, set_char_27,
    set_char_28, set_char_29, set_char_30, set_char_31,
    set_char_32, set_char_33, set_char_34, set_char_35,
    set_char_36, set_char_37, set_char_38, set_char_39,
    set_char_40, set_char_41, set_char_42, set_char_43,
    set_char_44, set_char_45, set_char_46, set_char_47,
    set_char_48, set_char_49, set_char_50, set_char_51,
    set_char_52, set_char_53, set_char_54, set_char_55,
    set_char_56, set_char_57, set_char_58, set_char_59,
    set_char_60, set_char_61, set_char_62, set_char_63,
    set_char_64, set_char_65, set_char_66, set_char_67,
    set_char_68, set_char_69, set_char_70, set_char_71,
    set_char_72, set_char_73, set_char_74, set_char_75,
    set_char_76, set_char_77, set_char_78, set_char_79,
    set_char_80, set_char_81, set_char_82, set_char_83,
    set_char_84, set_char_85, set_char_86, set_char_87,
    set_char_88, set_char_89, set_char_90, set_char_91,
    set_char_92, set_char_93, set_char_94, set_char_95,
    set_char_96, set_char_97, set_char_98, set_char_99,
    set_char_100, set_char_101, set_char_102, set_char_103,
    set_char_104, set_char_105, set_char_106, set_char_107,
    set_char_108, set_char_109, set_char_110, set_char_111,
    set_char_112, set_char_113, set_char_114, set_char_115,
    set_char_116, set_char_117, set_char_118, set_char_119,
    set_char_120, set_char_121, set_char_122, set_char_123,
    set_char_124, set_char_125, set_char_126, set_char_127,
    set1, set2, set3, set4, set_rule,
    put1, put2, put3, put4, put_rule,
    nop, bop, eop,
    push, pop,
    right1, right2, right3, right4,
    w0, w1, w2, w3, w4,
    x0, x1, x2, x3, x4,
    down1, down2, down3, down4,
    y0, y1, y2, y3, y4,
    z0, z1, z2, z3, z4,
    fnt_num_0, fnt_num_1, fnt_num_2, fnt_num_3,
    fnt_num_4, fnt_num_5, fnt_num_6, fnt_num_7,
    fnt_num_8, fnt_num_9, fnt_num_10, fnt_num_11,
    fnt_num_12, fnt_num_13, fnt_num_14, fnt_num_15,
    fnt_num_16, fnt_num_17, fnt_num_18, fnt_num_19,
    fnt_num_20, fnt_num_21, fnt_num_22, fnt_num_23,
    fnt_num_24, fnt_num_25, fnt_num_26, fnt_num_27,
    fnt_num_28, fnt_num_29, fnt_num_30, fnt_num_31,
    fnt_num_32, fnt_num_33, fnt_num_34, fnt_num_35,
    fnt_num_36, fnt_num_37, fnt_num_38, fnt_num_39,
    fnt_num_40, fnt_num_41, fnt_num_42, fnt_num_43,
    fnt_num_44, fnt_num_45, fnt_num_46, fnt_num_47,
    fnt_num_48, fnt_num_49, fnt_num_50, fnt_num_51,
    fnt_num_52, fnt_num_53, fnt_num_54, fnt_num_55,
    fnt_num_56, fnt_num_57, fnt_num_58, fnt_num_59,
    fnt_num_60, fnt_num_61, fnt_num_62, fnt_num_63,
    fnt1, fnt2, fnt3, fnt4,
    xxx1, xxx2, xxx3, xxx4,
    fnt_def1, fnt_def2, fnt_def3, fnt_def4,
    pre, post, post_post 
} dvi_op_code;
@ @<Global func...@>=
void handle_dvi_command(unsigned char*data,int len,Pixmap bp,GC gc,
        struct defined_font*cf);
@ @c
void handle_dvi_command(unsigned char*data,int len,Pixmap bp,GC gc,
        struct defined_font* cf)
{
    unsigned int ch;
    int rule_h,rule_w;
    int xh,xw,xx,xy,k,a,l,ii;
    struct defined_font*new_font;
    if(*data<=set4)
        @<Draw a character box@>@;
    else if(*data>=put1 && *data <= put4)
        @<Put a character@>@;
    else if(*data == set_rule || *data == put_rule)
        @<Draw a rule@>@;
    else if(*data == push)
        @<Push onto the stack@>@;
    else if(*data == pop)
        @<Pop the top of the stack@>@;
    else if(*data>=right1 && *data <= right4)
        @<Move right@>@;
    else if(*data >= w0 && *data <= w4)
        @<Fix |w|@>@;
    else if(*data >= x0 && *data <= x4)
        @<Fix |x|@>@;
    else if(*data >= down1 && *data <= down4)
        @<Move down@>@;
    else if(*data >= y0 && *data <= y4)
        @<Fix |y|@>@;
    else if(*data >= z0 && *data <= z4)
        @<Fix |z|@>@;
    else if(*data >= fnt_num_0 && *data <= fnt_num_63)
        @<Change the current font@>@;
    else if(*data >= fnt1 && *data <= fnt4)
        @<Change the multibyte current font@>@;
    else if(*data >= fnt_def1 && *data <= fnt_def4)
        @<Define a new font@>@;
}
@ @<Draw a character box@>={
    if(*data>=set1){
        ch=get_unsigned_int(&data[1],*data-set1+1); 
    } else ch=(unsigned int)*data;
    draw_character(ch,bp,gc,cf);
    dvi_stack[dvi_sp].h+=cf->width[(cf->char_info[ch-cf->bc]>>24)&0xff];
}
@ @<Put a character@>={
    ch=get_unsigned_int(&data[1],*data-put1+1); 
    draw_character(ch,bp,gc,cf);
}
@ @<Global func...@>=
void draw_character(unsigned int ch,Pixmap bp, GC gc,
        struct defined_font* cf);
@ @<Global func...@>=
void convert_to_x(int dx,int dy,int*xx,int*xy)
{
    *xx=(dx+65535)/65536;
    *xy=(dy+65535)/65536;
}
@ @c
void draw_character(unsigned int ch,Pixmap bp, GC gc, struct defined_font* cf)
{
    int xl,xs,xw,xh;
    convert_to_x(dvi_stack[dvi_sp].h,
            dvi_stack[dvi_sp].v-cf->height[(cf->char_info[ch-cf->bc]>>20)&0xf],
            &xl,&xs);
    convert_to_x(cf->width[(cf->char_info[ch-cf->bc]>>20)&0xf],
            cf->height[(cf->char_info[ch-cf->bc]>>20)&0xf]+
            cf->depth[(cf->char_info[ch-cf->bc]>>16)&0xf],
            &xw,&xh);
    XDrawRectangle(display,bp,gc,xl,xs,xw,xh);
}
@ @<Global func...@>=
int get_unsigned_int(unsigned char*data,int len)
{
    unsigned int ret;
    ret = 0;
    while(len > 0){
        ret <<= 8;
        ret |= *data;
        ++data;
        --len;
    }
    return ret;
}
@ @<Draw a rule@>={
    rule_h=get_int(&data[1],4);
    rule_w=get_int(&data[5],4);
    convert_to_x(rule_h,rule_w,&xh,&xw);
    convert_to_x(dvi_stack[dvi_sp].h,dvi_stack[dvi_sp].v,&xx,&xy);
    if(xh > 0 && xw > 0)
        XFillRectangle(display,bp,gc,xx,xy-xh,xw,xh);
    if(*data == set_rule)
        dvi_stack[dvi_sp].h += rule_w;
}
@ @<Global func...@>=
int get_int(unsigned char*data,int len)
{
    int ret;
    ret = 0;
    if(*data & 0x80)
        ret = ~0;
    while(len > 0){
        ret <<= 8;
        ret |= *data;
        ++data;
        --len;
    }
    return ret;
}
@ @<Push onto the stack@>=
push_state();
@ @<Pop the top of the stack@>=
pop_state();
@ @<Move right@>=
    dvi_stack[dvi_sp].h += get_int(&data[1],*data-right1+1);
@ @<Fix |w|@>={
    if(*data >= w1)
        dvi_stack[dvi_sp].w = get_int(&data[1],*data-w0);
    dvi_stack[dvi_sp].h += dvi_stack[dvi_sp].w;
}
@ @<Fix |x|@>={
    if(*data >= x1)
        dvi_stack[dvi_sp].x = get_int(&data[1],*data-x0);
    dvi_stack[dvi_sp].h += dvi_stack[dvi_sp].x;
}
@ @<Move down@>=
    dvi_stack[dvi_sp].v += get_int(&data[1],*data-down1+1);
@ @<Fix |y|@>={
    if(*data >= y1)
        dvi_stack[dvi_sp].y = get_int(&data[1],*data-y0);
    dvi_stack[dvi_sp].v += dvi_stack[dvi_sp].y;
}
@ @<Fix |z|@>={
    if(*data >= z1)
        dvi_stack[dvi_sp].z = get_int(&data[1],*data-z0);
    dvi_stack[dvi_sp].v += dvi_stack[dvi_sp].z;
}
@ @<Change the current font@>={
    current_font = get_new_font((unsigned int)(*data-fnt_num_0));
}
@ @<Global func...@>=
struct defined_font* get_new_font(unsigned int num);
@ @c
struct defined_font* get_new_font(unsigned int num)
{
   for(current_font=defined_font_list;current_font;
           current_font=current_font->next)
       if(current_font->num == num)
           break;
   return current_font;
}
@ @<Change the multibyte current font@>={
   ch = get_unsigned_int(&data[1],*data-fnt1+1); 
   current_font=get_new_font(ch);
}
@ @<Define a new font@>={
    k = (int)*data-fnt_def1+1;
    a = get_int(&data[13+k],1);
    l = get_int(&data[14+k],1);
    ch=get_unsigned_int(&data[1],*data-fnt_def1+1);
    fprintf(stderr,"ch is %d.\n",ch);
    if(!get_new_font(ch)){
        new_font=(struct defined_font*)malloc(sizeof(struct defined_font));
        for(ii=0;ii<a+l;++ii)
            font_name[ii] = data[k+15+ii];
        font_name[ii] = '\0';
        new_font=read_font_file(get_hash((char*)font_name));
        new_font->next = defined_font_list;
        defined_font_list = new_font;
        new_font->num = ch;
        fprintf(stderr,"Found a new font at %d.\n",new_font->num);
    }
}
@ @<Read the T...@>=
tfm_buf = read_file(tfm_db_file_name,&len);
if(!tfm_buf){
    fprintf(stderr,"Could not read file %s.\n",tfm_db_file_name);
    fflush(stderr);
    _exit(1);
}
tfm_buf_end = &tfm_buf[len];
for(num_tfm_lines=0,p=tfm_buf;p<tfm_buf_end;++p)
    if(*p == '\n')
        ++num_tfm_lines;
@ @<Global vari...@>=
unsigned char* tfm_buf;
unsigned char* tfm_buf_end;
int num_tfm_lines;
@ @<Global struc...@>=
struct tfm_db {
    char* tex_name;
    char* file_name;
};
@ @<Read the T...@>=
tfm_database = (struct tfm_db*)malloc(num_tfm_lines *
        sizeof(struct tfm_db)); 
for(p=tfm_buf,ii=0;ii<num_tfm_lines;++ii) {
   tfm_database[ii].tex_name = (char*)p;
   while(*p != ':')
       ++p; 
   *p = '\0';
   ++p;
   tfm_database[ii].file_name = (char*)p;
   while(*p != '\n')
       ++p;
    *p = '\0';
    ++p;
#if 0
    fprintf(stderr,"Assigned %s : %s\n",tfm_database[ii].tex_name,tfm_database[ii].file_name);
#endif
}
@ @<Global vari...@>=
struct tfm_db* tfm_database;
@ @<Global vari...@>=
char* input_file_name;
char* tfm_db_file_name;
char* output_file_name;
@ @<Global func...@>=
unsigned char* read_file(const char*,int*);
@ @c
unsigned char* read_file(const char*name,int*len)
{
    unsigned char* buf;
    struct stat filstat;
    int fd;
    int ii;
    int num_read;
    @<Open the file@>@;
    @<Get the size of the file@>@;
    buf = (unsigned char*)malloc(sizeof(unsigned char)* *len);
    if(!buf) {
        fprintf(stderr,"Could not allocate memory for the file.\n"); 
        fflush(stderr);
        _exit(1);
    }
    @<Now read the file@>@;
    close(fd);
    return buf;
}
@ @<Now read the file@>=
    for(ii=0;ii<*len;ii+=num_read){
        num_read = read(fd,&buf[ii],*len-ii); 
        if(num_read<0){
            fprintf(stderr,"Error reading from %s.\n",name); 
            fflush(stderr);
            _exit(1);
        }@+else if(num_read == 0){
            *len = ii;
            break;
        }
    }
@ @<Open the file@>=
fd = open(name,O_RDONLY);
if(fd<0) {
    fprintf(stderr,"Error opening %s.\n",name); 
    fflush(stderr);
    _exit(1);
}
@ @<Get the size of the file@>=
if(fstat(fd,&filstat)) {
    fprintf(stderr,"Error stat-ting %s.\n",name); 
    fflush(stderr);
    _exit(1);
}
@ @<Get the size of the file@>=
if(len) 
    *len = filstat.st_size;
else {
    fprintf(stderr,"Null pointer!!!\n"); 
    fflush(stderr);
    _exit(1);
}
