/* GTM2PERL database interface 
 *
 * Definitions & prototypes
 *
 */

// Flags to OR together to define how to pack a GVN
#define ZEROLEN_OK 1                    // GLVN with final subscript of "" OK
#define NO_WARN 2                       // No verbal warning for errors
#define NO_PREFIX 4                     // Don't prepend the usual prefix

// GTM v4.4-003 needs '_GT_NEED_TERMFIX' and '_GT_NEED_SIGFIX'
#define _GT_NEED_TERMFIX 1   // Restore terminal settings when exiting
#define _GT_NEED_SIGFIX 1    // Restore SIGINT handler after invoking GTM

#define _GT_GTMCI_LOC "/usr/local/gtm/xc/calltab.ci"

#ifdef _GT_NEED_TERMFIX
/* 
 * Store terminal settings from before GTM was invoked.  This
 * is a hack to get around GT.M v4.4-003's adjustment of term settings
 *
 */
#include <unistd.h>    // for STDIN_FILENO
#include <termios.h>   // for struct termios
struct termios *_GTMterm;
#endif

#ifdef _GT_NEED_SIGFIX
#include <signal.h>
#endif

// linked-list of pointers to the parts of a GTMglobal variable name
// used by; unpackgvn()
typedef struct _cppack  { char *loc; struct _cppack *next; } cppack;
typedef struct _strpack { char *address; unsigned length; char num; } strpack;

// This is the GTM environment object all functions will be associated with
typedef struct _gtmenv  {
  strpack *prefix;
  unsigned pfx_elem;
  unsigned pfx_length;
  char *last_err;
} GtmEnv;

unsigned _GTMinvoc; // Set to 1 if GTM has been started

// Given a GT.M error code, print the error message as a warning
// used by; any function interacting with GT.M
int    err_gtm(int errcode);

// Given an array of strings, return a valid MumpsGlobal Variable Name
char   *packgvn(GtmEnv *pfx, int len, strpack strs[],int flags);

// Given a global/local variable, return a list of pointers to it's
// separate elements.  NOTE: this is destructive to the passed-in string
cppack *unpackgvn(char *gvn);

// De-allocate the strings in a stringpack
void strpack_clear(strpack *start,int len);

