$AdminAccount = "BUILTIN\Administrators"
$FolderPath = "D:\profiles"

# Take ownership and grant full control to administrators
takeown /f $FolderPath /r /d y
icacls $FolderPath /setowner $AdminAccount /t /c
icacls $FolderPath /grant $AdminAccount":F" /t /c
