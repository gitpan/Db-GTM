use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my($GTMDIST)=$ENV{'gtm_dist'};  # Need GTM location

WriteMakefile(
    'NAME'		=> 'GTM',
    'VERSION_FROM'	=> 'GTM.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'GTM.pm', # retrieve abstract from module
       AUTHOR     => 'Steven Zeck <spzeck@ucdavis.edu>') : ()),
    'LIBS'		=> ["-L$GTMDIST -lgtmshr -Wl,-R,$GTMDIST"], 
    'DEFINE'		=> '', # e.g., '-DHAVE_SOMETHING'
    'INC'		=> "-I. -I$GTMDIST", 
);
