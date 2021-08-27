@echo off
rem Builds and uploads the extension to the marketplace
cd src
echo generate json...
json_from_yaml.jai
if NOT ["%errorlevel%"]==["0"] goto pop
copy /y VSCodeLocate.jai ..\out\VSCodeLocate.jai
copy /y asmCommands.json ..\out\asmCommands.jai
cd ..
echo vsce publish...
vsce publish
goto end
:pop
cd ..
:end
