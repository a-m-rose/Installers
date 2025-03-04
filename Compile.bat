7z.exe a .\temp\NINJAInstaller.7z NINJAInstaller.bat

> .\temp\install_config.txt (
    echo ;!@Install@!UTF-8!
    echo Title="NINJA Installer"
    echo ExecuteFile="NINJAInstaller.bat"
    echo ;!@InstallEnd@!
)

cd .\temp
copy /b 7zsd.sfx + install_config.txt + NINJAInstaller.7z NINJAInstaller.exe
cd ..