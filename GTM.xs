#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "gtmxc_types.h"   // For GTM call-in function prototypes
#include "string.h"        // strlen(), memcpy(), strncmp()
#include "GTM.h"           // my prototypes
#include "stdlib.h"        // setenv

int err_gtm(int errcode) {
  char *msgbuf = (char *)calloc(1024,sizeof(gtm_char_t));
  gtm_zstatus(msgbuf,1024);
  warn("GTM ERROR: (%d) %s\n", errcode, msgbuf);
  return errcode;
}

char *packgvn(GtmEnv *gtenv, int len, strpack strs[],int flags) {
  unsigned i,xlen=(gtenv && !(flags & NO_PREFIX))?gtenv->pfx_elem:0,sz,tmp; 
  char *ret=NULL,*loc,err=0,freestrs=0; strpack *seek;

  sz = ((len+xlen)>1) ? (len+xlen)*3 : 2; 
  if(xlen) {
    sz += (unsigned)gtenv->pfx_length;  
    for(i=0;i<xlen;i++) if(gtenv->prefix[i].num) sz -= 2;
  }
  if(len == 1 && strchr(strs[0].address,'\034')) {
    // Multidimensional array with \034 separators
    loc = strs[0].address; while( loc = index(loc,'\034') ) { len++; loc++; }
    loc = strs[0].address; freestrs=len; i = 0; sz += (len-1)*3;
    strs = (strpack *)calloc(len,sizeof(strpack)); 
    while( loc ) {
      ret = index(loc,'\034'); if(ret) *ret = '\0'; tmp = strlen(loc);
      strs[i].address = (char *)calloc(tmp+1,sizeof(char));
      strs[i].length  = tmp; memcpy(strs[i].address, loc, tmp); 
      loc = ret ? ret+1 : ret; i++;
    }
  } 
  // Validate global, calculate final GLVN size
  if(len||xlen) ret = (xlen) ? gtenv->prefix->address : strs[0].address; 
  if(len == 1 && *strs[0].address == '^') return strs[0].address;
  else if(!(len+xlen) || !(xlen || strs[0].length) || !ret || 
     !((*ret >= 'a' && *ret <= 'z') || (*ret >= 'A' && *ret <= 'Z'))
  ) err++; else for(i=0;i<len;i++) {
      if(!strs[i].length && !((flags & ZEROLEN_OK) && i==(len-1))) err++;
      else sz += strs[i].length; 
      if(is_number(strs[i].address)) { sz -= 2; strs[i].num++; }
  }
  if(err || !sz || sz > 255) {
    if(!(flags & NO_WARN)) warn("ERROR: Poorly-specified node name.\n"); 
    if(freestrs) strpack_clear(strs,len); return NULL;
  } else ret = (char *)calloc(sz+1,sizeof(char)); loc = ret; 

  *loc = '^'; loc++; for(i=0;i<(len+xlen);i++) {
    seek = (i<xlen) ? &gtenv->prefix[i] : &strs[i-xlen];
    if(i) {
      if(!seek->num) { *loc = '"'; loc++; }
      memcpy(loc, seek->address, seek->length); loc += seek->length;
      if(!seek->num) { *loc = '"'; loc++; }
      *loc = ((i+1) == (len+xlen)) ? ')' : ','; loc++;
    } else {
      memcpy(loc, seek->address, seek->length); loc += seek->length;
      if((len+xlen) > 1) { *loc = '('; loc++; }
    }
  }
  if(freestrs) strpack_clear(strs,len); return ret;
}

int is_number(char *i) {
  char dec=0; 

  if(*i == '-') i++; if(*i == '0') {
    i++; if(*i != '.') return 0; else { dec++; i++; }
  } else if(*i < '0' || *i > '9') return 0; else i++;
  for(;*i;i++) {
    if(*i == '.') { if(dec) return 0; else { dec++; } }
    else if(*i < '0' || *i > '9') return 0;
  }
  return (dec && (*(i-1) == '0')) ? 0 : 1;
}

cppack *unpackgvn(char *gvn) {
  char *at = gvn, *seek, quot = 0, err = 0; cppack *ret, *working, *new;

  if(!gvn || (*gvn != '^') || strlen(gvn) > 255) return NULL;
  ret = (cppack *)calloc(1,sizeof(cppack));
  at++; ret->loc = at; seek = index(at, '('); 
  if(!seek) return ret; else { *seek = '\0'; at = seek+1; }
  seek = rindex(at, ')'); if(!seek) {free(ret); return NULL;} else *seek='\0';
  working = ret; while(at) {
    if(*at == '"') { 
      at++; seek = index(at, '"'); 
      while(seek && seek[1] == '"') { seek = index(&seek[2],'"'); }
      if(!seek) err++; else { *seek = '\0'; seek += 2; }
    } else { seek = index(at, ','); if(seek) { *seek = '\0'; seek++; } }
    if(!err && *at) { 
      new = (cppack *)calloc(1,sizeof(cppack));
      new->loc = at; working->next = new; working = new; at = seek; 
    } else { at = NULL; }
  }
  return ret;
}

void strpack_clear(strpack *start,int len) {
  unsigned i; strpack *zap; if(start) {
    for(i=0;i<len;i++) free(start[i].address); free(start); 
  }
}


MODULE = Db::GTM		PACKAGE = GTMDB

PROTOTYPES: ENABLE

GtmEnv *
new(...)
	ALIAS:
	  TIEHASH = 1
	  TIESCALAR = 2
	  GtmEnvPtr::sub  = 3
	CODE:
	{
	  gtm_status_t status; strpack *strp, *gvnprefix; 
	  GtmEnv *setup = (GtmEnv *)calloc(1,sizeof(GtmEnv)), *sub; 
	  int i,len,tlen=0; char *test,err=0;
#ifdef _GT_NEED_SIGFIX
	  sig_t sigint;
#endif
	
	  if(items > 256) { warn("Init fail; excessive prefixes...\n"); err++; }
	  else if(items < 2) { warn("Init fail; no prefix given...\n"); err++; }
	  else {
	    if(ix == 3 && sv_isa(ST(0),"GtmEnvPtr") ) {
	      sub = (GtmEnv *)SvIV((SV*)SvRV(ST(0))); 
              len = sub->pfx_elem; tlen = sub->pfx_length;
	    } else {
              test = (char *)SvPV(ST(1),i); len = 0; tlen = 0;
	      if(!((*test>='a' && *test<='z')||(*test>='A' && *test<='Z'))) {
	        warn("Init fail; invalid starting prefix character.\n"); err++;
	      } 
	    }
	    setup->prefix = (strpack *)calloc(items+len-1,sizeof(strpack));
	    if(ix==3&&sv_isa(ST(0),"GtmEnvPtr")) for(i=0;i<sub->pfx_elem;i++) {
	      strp = &sub->prefix[i]; gvnprefix = &setup->prefix[i];
	      gvnprefix->length = strp->length; gvnprefix->num = strp->num;
	      gvnprefix->address=(char *)calloc(strp->length+1,sizeof(char));
	      memcpy(gvnprefix->address, strp->address, strp->length);
	    }
	    for(i=1;i<items;i++) {
	      strp = &setup->prefix[i-1+len];
              test = (char *)SvPV(ST(i), strp->length);
              strp->address = (char *)calloc((strp->length)+1,sizeof(char));
	      memcpy(strp->address, test, strp->length);
	      strp->num = is_number(strp->address);
	      if(!strp->length) { warn("Init fail; null subscript.\n"); err++; }
              else tlen += strp->length;
	    }
	    if(tlen > 255) { warn("Init fail; prefix too long...\n"); err++; }
	    if(err) { strpack_clear(setup->prefix,items-1); free(setup); } 
            else { setup->pfx_elem = (items+len-1); setup->pfx_length = tlen; }
          } 
          if(!err) { 
	    if(!_GTMinvoc) { // Save terminal settings to restore during END()
#ifdef _GT_NEED_TERMFIX
              _GTMterm = (struct termios *)calloc(1,sizeof(struct termios));
	      tcgetattr(STDIN_FILENO, _GTMterm);
#endif
#ifdef _GT_NEED_SIGFIX
	      sigint = signal(SIGINT, SIG_DFL); // Save SIGINT handler
#endif
	      setenv("GTMCI",_GT_GTMCI_LOC,0);
              status = gtm_init(); 
#ifdef _GT_NEED_SIGFIX
	      signal(SIGINT, sigint); // Restore SIGINT handler
#endif
            } else status = 0;
            if(status) { 
	      err_gtm(status);strpack_clear(setup->prefix,items-1);free(setup); 
	      XSRETURN_UNDEF; 
            } else { RETVAL = setup; _GTMinvoc = 1; }
	  } else XSRETURN_UNDEF;
	}
	OUTPUT:
	RETVAL

void
gvn2list(...)
	ALIAS:
	  _str2list = 1
	  GTM::gvn2list  = 2
	  GTM::_str2list  = 3
	  GtmEnvPtr::gvn2list  = 4
	  GtmEnvPtr::_str2list  = 5
	PPCODE:
	{
          cppack *start = NULL, *next; SV *ret; unsigned s , x; char *glvn;
	  s = (ix < 4) ? 0 : 1; if(items < s) XSRETURN_UNDEF; 
	  start = unpackgvn( SvPV(ST(s),x) ); while(start) {
	    ret = sv_newmortal(); sv_setpv(ret, start->loc); XPUSHs(ret);
	    next = start->next; free(start); start = next;
          }
	}

void
list2gvn(...)
	ALIAS:
	  _list2str = 1
	  GTM::list2gvn = 2
	  GTM::_list2str = 3
	  GtmEnvPtr::list2gvn = 4
	  GtmEnvPtr::_list2str = 5
	  GtmEnvPtr::node = 6
	PPCODE:
	{
	  strpack *args; 
	  GtmEnv *pfx = (ix<4) ? NULL : (GtmEnv *)SvIV((SV*)SvRV(ST(0)));
	  int i,s = (ix<4) ? 0 : 1; SV *ret;
	  char *glvn=NULL, *n=NULL; unsigned long status; gtm_string_t value;

	  EXTEND(SP,1); if(items>s) {
	    args = (strpack *)calloc(items-s,sizeof(strpack));
            for(i=s;i<items;i++) 
              args[i-s].address = (char *)SvPV(ST(i),args[i-s].length);
	    glvn = packgvn(pfx,items-s,args,(ix<4) ? NO_PREFIX : 0); 
            n=args[0].address; free(args); 
	  } else { glvn = packgvn(pfx,0,NULL,0); }
	  if(glvn) { 
	    ret = sv_newmortal(); sv_setpv(ret, glvn); PUSHs(ret);
	    if(glvn != n) free(glvn);
	  } else PUSHs(&PL_sv_undef); 
	}

void
END()
	PPCODE:
	{
	   if(_GTMinvoc) gtm_exit();
#ifdef _GT_NEED_TERMFIX
	   if(_GTMinvoc){ tcsetattr(STDIN_FILENO,0,_GTMterm); free(_GTMterm); }
#endif
	}

MODULE = Db::GTM		PACKAGE = GtmEnvPtr

void
DESTROY(gt_env)
	GtmEnv *gt_env
	PPCODE:
	{
	   strpack_clear(gt_env->prefix,gt_env->pfx_elem); free(gt_env); 
	}

void
get(gt_env,...)
	GtmEnv *gt_env
	ALIAS:
	  retrieve = 1
	  FETCH = 2
	  EXISTS = 3
	  exists = 4
	PPCODE:
	{
	  strpack *args; int i; char *glvn=NULL, *n=NULL; 
	  unsigned long exst=0, status; gtm_string_t value; 
	  SV *ret=sv_newmortal(); EXTEND(SP, 1);

	  if(items>1) { 
            args = (strpack *)calloc(items-1,sizeof(strpack));
	    for(i=1;i<items;i++) 
              args[i-1].address = (char *)SvPV(ST(i),args[i-1].length);
	    glvn = packgvn(gt_env,items-1,args,0);n=args[0].address;free(args); 
	  } else { glvn = packgvn(gt_env,0,NULL,0); }
	  if(glvn) {
	    value.address = (char *)calloc(32770,sizeof(char)); 
	    status = gtm_ci("get",&value,glvn,&exst); if(glvn != n) free(glvn); 
	
            if(status) { err_gtm(status); PUSHs(&PL_sv_undef); }
            else if(ix == 3 || ix == 4) PUSHs(newSViv(exst ? 1 : 0));
            else if(ix == 5)            PUSHs(newSViv(exst > 1 ? 1 : 0));
            else if(exst == 0 || exst == 10) PUSHs(&PL_sv_undef); 
	    else { sv_setpvn(ret, value.address, value.length); PUSHs(ret); } 
            free(value.address); 
          }   else PUSHs(&PL_sv_undef); // Bad GVN name
	}

void
set(gt_env,...)
	GtmEnv *gt_env
	ALIAS:
	  store = 1
	  STORE = 2
	PPCODE:
	{
	  strpack *args; int i; char *glvn=NULL, *n=NULL; unsigned long status; 

	  if(items>2) {
	    args = (strpack *)calloc(items-1,sizeof(strpack));
	    for(i=1;i<(items-1);i++) 
              args[i-1].address = (char *)SvPV(ST(i),args[i-1].length);
	    glvn = packgvn(gt_env,items-2,args,0);n=args[0].address;free(args); 
	  } else { glvn = packgvn(gt_env,0,NULL,0); }
	  EXTEND(SP,1); if(glvn) {
	    status = gtm_ci("set",glvn,(char *)SvPV(ST(items-1),i));
	    if(glvn != n) free(glvn); if(status) {
	      err_gtm(status); XPUSHs(newSViv(status)); // GTM error
	    } else XPUSHs(newSViv(0)); // Set OK
          }   else XPUSHs(newSViv(1)); // Bad GVN name
	}

void
order(gt_env,...)
	GtmEnv *gt_env
	ALIAS:
	  next = 1
	  NEXTKEY = 2
	  first = 3
	  FIRSTKEY = 4
	  haschildren = 5
	  revorder = 6
	  prev = 7
	  last = 8
	PPCODE:
	{
	  strpack *args; int i, aq=0, dir=(ix>5) ? -1 : 1; SV *ret;
	  char *glvn=NULL, *n=NULL, *addquot= ""; 
	  unsigned long status; gtm_string_t value;

	  if(items==1 || ix==3 || ix==4 || ix==5 || ix==8) { items++; aq++; }
	  args = (strpack *)calloc(items-1,sizeof(strpack));
          for(i=1;i<(items-aq);i++) 
            args[i-1].address = (char *)SvPV(ST(i),args[i-1].length);
	  if(aq) { args[items-2].address = addquot; args[items-2].length  = 0; }
	  glvn = packgvn(gt_env,items-1,args,ZEROLEN_OK); 
	  n=args[0].address; free(args); 
	  EXTEND(SP,1); if(glvn) {
	    value.address = (char *)calloc(260,sizeof(char)); 
	    status = gtm_ci("order",&value,glvn,dir);
	    if(status) { err_gtm(status); PUSHs(&PL_sv_undef); } 
	    else if(!value.length) PUSHs(&PL_sv_undef); 
	    else if(ix == 5) PUSHs(newSViv(1)); 
            else {
	      //ret = sv_newmortal();
	      //sv_setpvn(ret, value.address, value.length); PUSHs(ret);
	      PUSHs(newSVpvn(value.address, value.length));
	    }
	    if(glvn != n) free(glvn); free(value.address);
          } else PUSHs(&PL_sv_undef); // Bad GVN name
	}

void
kill(gt_env,...)
	GtmEnv *gt_env
	ALIAS:
	  ks = 1
	  kv = 2
	  DELETE = 3
	  CLEAR = 4
	PPCODE:
	{
	  strpack *args; int i; char *glvn=NULL, *n=NULL; 
	  unsigned long status=1; 

          if(items>1) {
	    args = (strpack *)calloc(items-1,sizeof(strpack));
            for(i=1;i<items;i++) 
              args[i-1].address = (char *)SvPV(ST(i),args[i-1].length);
	    glvn = packgvn(gt_env,items-1,args,0); 
	    n = args[0].address; free(args); 
	  } else { glvn = packgvn(gt_env,0,NULL,0); }
	  EXTEND(SP,1); if(glvn) {
	    switch(ix) {
	     case 0: case 3: case 4:
                     status = gtm_ci("kill",glvn); break;
	     case 1: status = gtm_ci("ks",glvn);   break;
	     case 2: status = gtm_ci("kv",glvn);   break;
	     default: break;
	    }
	    if(glvn != n) free(glvn); if(status) {
	      err_gtm(status); PUSHs(newSViv(status));
	    } else PUSHs(newSViv(0)); // Kill OK
          }   else PUSHs(newSViv(1)); // Bad GVN name
	}

void
query(gt_env,...)
	GtmEnv *gt_env
	PPCODE:
	{
	  unsigned long status=1; SV *ret; char *glvn=NULL, *n=NULL, **brk; 
	  strpack *args; cppack *start=NULL,*next; gtm_string_t value;
	  int i,y,z; 

	  if(items>1) {
	    args = (strpack *)calloc(items-1,sizeof(strpack));
	    for(i=1;i<items;i++) 
              args[i-1].address = (char *)SvPV(ST(i),args[i-1].length);
	    glvn=packgvn(gt_env,items-1,args,0); n=args[0].address; free(args); 
	  } else { glvn = packgvn(gt_env,0,NULL,0); }
	  if(glvn) {
	    value.address = (char *)calloc(260,sizeof(char)); 
	    status = gtm_ci("query",&value,glvn);
	    if(glvn != n) free(glvn); if(status) {
              err_gtm(status); XPUSHs(&PL_sv_undef);
	    } else {
	      value.address[value.length] = '\0'; 
	      start = unpackgvn(value.address); z=0; 
	        for(i=0;i<(gt_env->pfx_elem);i++) {
		if(!start && 
	            strncmp(start->loc,
                            gt_env->prefix[i].address,
                            gt_env->prefix[i].length) 
                  ) z++;
		if(start) { next = start->next; free(start); start = next; }	
	      }
	      if(z) { // We're not in kansas anymore
		while(start) { next = start->next; free(start); start = next; }
	      } else while(start) {
	        ret = sv_newmortal(); sv_setpv(ret, start->loc); XPUSHs(ret);
		next = start->next; free(start); start = next;
              }
	      free(value.address);
	    }
          } else XPUSHs(&PL_sv_undef);
	}

void
children(gt_env,...)
	GtmEnv *gt_env
	PPCODE:
	{
	  char *glvnbuf=(char *)calloc(260,sizeof(char)),*glvn=NULL,*n=NULL; 
	  strpack *args; gtm_string_t value; int i; SV *ret; char *loc;
	  unsigned long len, status=0, count=0; 

	  if(items>1) {
	    args = (strpack *)calloc(items-1,sizeof(strpack));
	    for(i=1;i<items;i++) 
              args[i-1].address = (char *)SvPV(ST(i),args[i-1].length);
	    glvn=packgvn(gt_env,items-1,args,0); n=args[0].address; free(args); 
	  } else { glvn = packgvn(gt_env,0,NULL,0); }
	  if(glvn) {
	    len = strlen(glvn); if(len > 255) {
              warn("GTM-ERR: Passed-in node name too long\n"); loc = NULL; 
	    } else if( glvn[len-1] == ')' ) {
  	      memcpy(glvnbuf,glvn,len); loc=glvnbuf+len-1; *loc = ','; loc++;
	    } else {
	      memcpy(glvnbuf,glvn,len); loc=glvnbuf+len;   *loc = '('; loc++;
	    }
            if(loc) {
              value.address = (char *)calloc(260,sizeof(char));

              sprintf(loc,"\"\")"); status = gtm_ci("order",&value,glvnbuf,1); 
	      while(!status && value.length) {
	        value.address[value.length] = '\0'; 
		XPUSHs(newSVpvn(value.address, value.length));

	        // the \"s aren't necessary around canonical numbers but ehh.
	        // It's faster this way than to check + atof/atoi
	        sprintf(loc,"\"%s\")",value.address);
	        status = gtm_ci("order",&value,glvnbuf,1); 
              }
	      if(status) err_gtm(status); 
	      free(value.address); 
            }
            if(glvn != n) free(glvn);
          }
	  free(glvnbuf); 
	}

void
copy(...)
	ALIAS:
	  GTM::copy  = 4
	  GTMDB::copy  = 8
	  merge = 1
	  GTM::merge  = 5
	  GTMDB::merge  = 9
	  clobber = 2
	  GTM::clobber = 6
	  GTMDB::clobber = 10
	  overwrite = 3
	  GTM::overwrite = 7
	  GTMDB::overwrite = 11
	PPCODE:
	{
	  strpack *args; int i,mid=0,ov=(ix & 2)?1:0,ob=(ix<4)?1:0; SV *ret;
	  char *src=NULL,*dst=NULL,s=1,d=1; unsigned long status; strpack value;
	  GtmEnv *gt_env = (ob) ? (GtmEnv *)SvIV((SV*)SvRV(ST(0))) : NULL;

	  EXTEND(SP,1); if(items == (ob+2)) { 
	    // Two arguments passed in...
	    if(!sv_isa(ST(ob),"GtmEnvPtr")) { src=(char *)SvPV(ST(ob),i); s=0; }
            else src = packgvn((GtmEnv *)SvIV((SV*)SvRV(ST(ob))),0,NULL,0);
	    if(!sv_isa(ST(ob+1),"GtmEnvPtr")){dst=(char *)SvPV(ST(ob+1),i);d=0;}
	    else dst = packgvn((GtmEnv *)SvIV((SV*)SvRV(ST(ob+1))),0,NULL,0);
	  } else if(ob && items == 2 && sv_isa(ST(1),"GtmEnvPtr") ) {
            src = packgvn((GtmEnv *)SvIV((SV*)SvRV(ST(1))),0,NULL,0);
	    dst = packgvn(gt_env,0,NULL,0); 
	  } else if(items>ob) {
	    args = (strpack *)calloc(items-ob,sizeof(strpack)); 
	    for(i=ob;i<items;i++) {
              args[i-ob].address = (char *)SvPV(ST(i),args[i-ob].length);
	      if(!args[i-ob].length && !mid) mid = i-ob;
	    }
	    if(!mid && ob) { // No target specified, assume it's us
	      src = packgvn(gt_env,items-1,args,0); 
	      dst = packgvn(gt_env,0,NULL,0); 
	    } else {
	      src = packgvn(gt_env,mid,args,0); 
	      dst = packgvn(gt_env,(items-(mid+1+ob)),&args[mid+1],0);
            }
            free(args); 
	  }
	  if(src && dst) {
	    if(!ov) status = gtm_ci("copy",src,dst); 
	    else    status = gtm_ci("clone",src,dst); 
	    if(status) { err_gtm(status); PUSHs(newSViv(status)); } 
	    else PUSHs(newSViv(0));
	  } else PUSHs(newSViv(1)); // Bad GVN name(s)
	  if(s && src) free(src); if(d && dst) free(dst); 
	}

void
getprefix(gt_env)
	GtmEnv *gt_env
	PPCODE:
	{
          strpack *x; int i; SV *ret; EXTEND(SP,gt_env->pfx_elem);
	  if(gt_env->prefix) for(i=0;i<(gt_env->pfx_elem);i++) {
	    x=&gt_env->prefix[i]; PUSHs(newSVpvn(x->address, x->length));
          }
	}
