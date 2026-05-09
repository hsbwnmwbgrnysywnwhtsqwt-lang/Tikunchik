@echo off
echo Installing dependencies...
pip install -r requirements.txt
pip install pyinstaller

echo Building Tikunchik.exe...
pyinstaller --onefile --windowed --name Tikunchik tikunchik.py

echo.
echo Done! Find Tikunchik.exe in dist\
pause
