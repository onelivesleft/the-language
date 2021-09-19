@echo off
rem Builds and uploads the extension to the marketplace
cd src
echo generate json...
json_from_yaml.jai
if NOT ["%errorlevel%"]==["0"] goto pop
echo Copy VSCodeLocate.jai...
copy /y VSCodeLocate.jai ..\out\VSCodeLocate.jai
echo Copy asmCommands.json...
copy /y asmCommands.json ..\out\asmCommands.json
cd ..
echo vsce publish...
vsce publish
goto end
:pop
cd ..
:end
