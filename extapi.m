extapi	; MUMPS-to-C/PERL external API functions
	; These are very raw functions and they provide unrestricted
	; direct access to every part of the M database.  This is 
	; probably not a good thing.  Some checking or restrictions
	; would be handy.  
	; -spz2
get(glvn,exist)	; Fetch $D of variable & it's value
	s exist=$d(@glvn) q $g(@glvn,"")
set(glvn,val)	; Set variable to given value
	s @glvn=val q
kill(glvn)	; Kill specified global + all subscripts
	k @glvn q
killval(glvn)	; Kill specified global only, not subs (GT.M specific)
	zwithdraw @glvn q
killsub(glvn)	; Kill subscripts of global, but not global itself (GT.M)
	n save,d s d=$D(@glvn) 
	if (d=1)!(d=11) s d=1,save=@glvn 
	k @glvn s:d=1 @glvn=save q
copy(gl1,gl2)	; Copy one global into another
	m @gl2=@gl1 q
clobber(gl1,gl2); Clone one global to another
	n tmp m tmp=@gl1 k @gl2 m @gl2=tmp
order(glvn,dir)	; $Order of given globalname
	q $o(@glvn,dir)
query(glvn)	; $Query of given globalname
	q $q(@glvn)
