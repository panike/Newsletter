set cindent shiftwidth=4 tabstop=4 expandtab
syn on
hi Comment ctermfg=6
map <F5> :s/_/x/gc<Return>
map <F6> :s/ TeX//<Return>j
map <F7> :s/@s /\\def\\/<Return>j
map <F8> :s/\\def\\\(.\+\)$/&{\\tt \1}/<Return>j
map <F9> :s/x/\\_/gc<Return>
 
