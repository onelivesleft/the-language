@echo off
cd src
echo generate json...
json_from_yaml.jai
if NOT ["%errorlevel%"]==["0"] goto pop
cd ..
echo vsce publish...
vsce publish
goto end
:pop
cd ..
:end
