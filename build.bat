@echo off
rem Builds the extension
cd src
echo generate json...
json_from_yaml.jai
if NOT ["%errorlevel%"]==["0"] goto pop
copy /y VSCodeLocate.jai ..\out\VSCodeLocate.jai
cd ..
echo vsce package...
vsce package
goto end
:pop
cd ..
:end
