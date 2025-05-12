Для корректной работы необходимо задать следующие перемнные (для PowerShell)
$Env:YC_TOKEN=$(yc iam create-token)
$Env:YC_CLOUD_ID=$(yc config get cloud-id)
$Env:YC_FOLDER_ID=$(yc config get folder-id)

Необходимо указать ваш открытый ssh-ключ в файле cloud-init.yaml.tftpl
