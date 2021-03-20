@echo off
cd src
echo generate json...
json_from_yaml.jai
if NOT ["%errorlevel%"]==["0"] goto pop
cd ..
echo vsce package...
vsce package
goto end
:pop
cd ..
:end
