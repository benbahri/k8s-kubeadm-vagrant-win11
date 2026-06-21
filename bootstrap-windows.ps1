#Requires -Version 5.1

<#
.SYNOPSIS
Prépare Windows 11 pour les ateliers Kubernetes et démarre le cluster Vagrant.

.DESCRIPTION
Installe, uniquement s'ils sont absents, Git/Git Bash, VirtualBox, Vagrant,
kubectl, Visual Studio Code, Docker Desktop et MSYS2. Configure Git Bash comme
terminal VS Code par défaut, puis installe Zsh et Oh My Zsh dans MSYS2.

Docker Desktop est installé sur la machine HOTE pour l'atelier 01 (rappel
conteneurs : build/run d'images en local). Le cluster, lui, tourne sous
containerd dans les VMs ; Docker n'y est volontairement pas installé.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\bootstrap-windows.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\bootstrap-windows.ps1 -NoVagrantUp
#>

[CmdletBinding()]
param(
    [switch]$NoVagrantUp,
    [switch]$SkipZsh,
    [switch]$SkipDocker,
    [Parameter(DontShow)][switch]$ElevatedRelaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Step 'Élévation en administrateur'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-ElevatedRelaunch'
    )
    if ($NoVagrantUp) { $arguments += '-NoVagrantUp' }
    if ($SkipZsh) { $arguments += '-SkipZsh' }
    if ($SkipDocker) { $arguments += '-SkipDocker' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    exit
}

$logFile = Join-Path $env:TEMP 'kubeadm-bootstrap-windows.log'
try {
    Start-Transcript -Path $logFile -Append -ErrorAction Stop | Out-Null
} catch {
    Write-Warning "Impossible de créer le journal $logFile : $($_.Exception.Message)"
}

# Une erreur winget se produisait auparavant dans la console administrateur,
# qui se fermait immédiatement. Ce trap conserve le message et l'emplacement du
# journal avant de rendre la main à l'utilisateur.
trap {
    Write-Host "`nECHEC DU BOOTSTRAP" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Journal : $logFile" -ForegroundColor Yellow
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    if ($ElevatedRelaunch -and [Environment]::UserInteractive) {
        [void](Read-Host 'Appuyez sur Entrée pour fermer cette fenêtre')
    }
    exit 1
}

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw "winget est absent. Installez ou mettez à jour 'App Installer' depuis le Microsoft Store, puis relancez ce script."
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][scriptblock]$IsInstalled
    )

    if (& $IsInstalled) {
        Write-Host "[OK] $Name est déjà installé."
        return
    }

    Write-Step "Installation de $Name"
    & winget.exe install --id $Id --exact --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "L'installation de $Name a échoué (code winget $LASTEXITCODE)."
    }
}

$gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
$virtualBoxManage = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
$vagrantCandidates = @(
    (Join-Path $env:ProgramFiles 'HashiCorp\Vagrant\bin\vagrant.exe'),
    (Join-Path $env:ProgramFiles 'Vagrant\bin\vagrant.exe'),
    'C:\HashiCorp\Vagrant\bin\vagrant.exe'
)
$vagrant = $vagrantCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$code = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
$dockerDesktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
$msysBash = 'C:\msys64\usr\bin\bash.exe'
$kubectlLink = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\kubectl.exe'

Install-WingetPackage 'Git et Git Bash' 'Git.Git' { Test-Path $gitBash }
Install-WingetPackage 'VirtualBox' 'Oracle.VirtualBox' { Test-Path $virtualBoxManage }
Install-WingetPackage 'Vagrant' 'Hashicorp.Vagrant' {
    [bool]($vagrantCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
}
Install-WingetPackage 'kubectl' 'Kubernetes.kubectl' {
    (Test-Path $kubectlLink) -or (Get-Command kubectl.exe -ErrorAction SilentlyContinue)
}
Install-WingetPackage 'Visual Studio Code' 'Microsoft.VisualStudioCode' {
    (Test-Path $code) -or (Get-Command code.cmd -ErrorAction SilentlyContinue)
}
if (-not $SkipDocker) {
    # Docker Desktop sert UNIQUEMENT sur l'hôte pour l'atelier 01 (build/run
    # d'images en local). Il s'appuie sur WSL2 ; un redémarrage Windows et
    # l'activation de WSL2 peuvent être nécessaires au premier lancement.
    Install-WingetPackage 'Docker Desktop' 'Docker.DockerDesktop' {
        (Test-Path $dockerDesktop) -or (Get-Command docker.exe -ErrorAction SilentlyContinue)
    }
}
if (-not $SkipZsh) {
    Install-WingetPackage 'MSYS2' 'MSYS2.MSYS2' { Test-Path $msysBash }
}

# Rend immédiatement visibles les exécutables ajoutés au PATH, sans devoir
# fermer la console courante.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

Write-Step "Configuration de l'alias k pour kubectl"

# Git Bash est le terminal VS Code par défaut dans ce lab.
$gitBashRc = Join-Path $env:USERPROFILE '.bashrc'
if (-not (Test-Path $gitBashRc) -or
    -not (Select-String -Path $gitBashRc -Pattern '^\s*alias\s+k=' -Quiet)) {
    Add-Content -Path $gitBashRc -Value "alias k='kubectl'" -Encoding ASCII
}
Write-Host "[OK] Alias Git Bash : $gitBashRc"

# Configure également l'alias dans Windows PowerShell 5.1 et PowerShell 7.
$documents = [Environment]::GetFolderPath('MyDocuments')
$powerShellProfiles = @(
    (Join-Path $documents 'WindowsPowerShell\profile.ps1'),
    (Join-Path $documents 'PowerShell\profile.ps1')
)
foreach ($profileFile in $powerShellProfiles) {
    New-Item -ItemType Directory -Path (Split-Path $profileFile -Parent) -Force | Out-Null
    if (-not (Test-Path $profileFile) -or
        -not (Select-String -Path $profileFile -Pattern '^\s*Set-Alias\s+(?:-Name\s+)?k\s+' -Quiet)) {
        Add-Content -Path $profileFile -Value 'Set-Alias -Name k -Value kubectl' -Encoding ASCII
    }
}
Set-Alias -Name k -Value kubectl -Scope Global
Write-Host '[OK] Alias PowerShell : k -> kubectl'

# admin.conf sera créé dans ce dossier par master.sh. Enregistrer son chemin dès
# maintenant permet aux nouveaux terminaux d'utiliser directement le cluster.
$hostKubeconfig = Join-Path $PSScriptRoot 'admin.conf'
$env:KUBECONFIG = $hostKubeconfig
[Environment]::SetEnvironmentVariable('KUBECONFIG', $hostKubeconfig, 'User')
Write-Host "[OK] KUBECONFIG utilisateur : $hostKubeconfig"

Write-Step 'Configuration de Git Bash comme terminal VS Code par défaut'
$settingsDirectory = Join-Path $env:APPDATA 'Code\User'
$settingsFile = Join-Path $settingsDirectory 'settings.json'
New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null

if (Test-Path $settingsFile) {
    $settings = Get-Content $settingsFile -Raw
    if ([string]::IsNullOrWhiteSpace($settings)) {
        $settings = "{`r`n  `"terminal.integrated.defaultProfile.windows`": `"Git Bash`"`r`n}"
    } else {
        $propertyPattern = '(?m)("terminal\.integrated\.defaultProfile\.windows"\s*:\s*)"[^"]*"'
        if ($settings -match $propertyPattern) {
            $settings = $settings -replace $propertyPattern, '$1"Git Bash"'
        } else {
            $settings = $settings -replace '(?s)^\s*\{', "{`r`n  `"terminal.integrated.defaultProfile.windows`": `"Git Bash`","
        }
    }
} else {
    $settings = @"
{
  "terminal.integrated.defaultProfile.windows": "Git Bash"
}
"@
}
Set-Content -Path $settingsFile -Value $settings -Encoding UTF8
Write-Host "[OK] Configuration VS Code : $settingsFile"

if (-not $SkipZsh) {
    Write-Step 'Installation de Zsh dans MSYS2'
    # L'installation MSYS2 fournie par winget est minimale. coreutils fournit
    # notamment `id`, requis par l'installateur officiel de Oh My Zsh.
    & $msysBash -lc 'pacman -Sy --needed --noconfirm coreutils grep sed zsh git curl'
    if ($LASTEXITCODE -ne 0) {
        throw "L'installation de Zsh dans MSYS2 a echoue."
    }
    & $msysBash -lc 'command -v id >/dev/null && command -v zsh >/dev/null'
    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 ne trouve pas les commandes id ou zsh dans son PATH."
    }

    Write-Step 'Installation de Oh My Zsh dans MSYS2'
    $ohMyZshDirectory = 'C:\msys64\home\{0}\.oh-my-zsh' -f $env:USERNAME
    $ohMyZshMainFile = Join-Path $ohMyZshDirectory 'oh-my-zsh.sh'
    if (Test-Path $ohMyZshMainFile) {
        Write-Host '[OK] Oh My Zsh est déjà installé.'
    } else {
        # Nettoie une éventuelle installation partielle laissée par un essai
        # précédent avant que l'installateur ne relance le clone Git.
        Remove-Item $ohMyZshDirectory -Recurse -Force -ErrorAction SilentlyContinue
        # Ne pas imbriquer $(curl ...) dans bash -lc : Windows PowerShell 5.1
        # remanie les guillemets et tronque la substitution de commande.
        $installerWindowsPath = 'C:\msys64\tmp\install-ohmyzsh.sh'
        Invoke-WebRequest `
            -UseBasicParsing `
            -Uri 'https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh' `
            -OutFile $installerWindowsPath

        $env:RUNZSH = 'no'
        $env:CHSH = 'no'
        $env:KEEP_ZSHRC = 'yes'
        try {
            # Le shell de connexion initialise le PATH MSYS2 (/usr/bin), sans
            # quoi l'installateur ne trouve pas `id` même si coreutils est là.
            & $msysBash -lc '/tmp/install-ohmyzsh.sh'
            $ohMyZshExitCode = $LASTEXITCODE
        } finally {
            Remove-Item $installerWindowsPath -Force -ErrorAction SilentlyContinue
            Remove-Item Env:RUNZSH, Env:CHSH, Env:KEEP_ZSHRC -ErrorAction SilentlyContinue
        }

        if ($ohMyZshExitCode -ne 0) {
            throw "L'installation de Oh My Zsh a echoue (code $ohMyZshExitCode)."
        }
    }

    $zshRc = Join-Path (Split-Path $ohMyZshDirectory -Parent) '.zshrc'
    if (-not (Test-Path $zshRc) -or
        -not (Select-String -Path $zshRc -Pattern '^\s*alias\s+k=' -Quiet)) {
        Add-Content -Path $zshRc -Value "alias k='kubectl'" -Encoding ASCII
    }
    Write-Host "[OK] Alias Zsh : $zshRc"
}

Write-Step 'Vérification de la virtualisation matérielle'
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
if ($processor.VirtualizationFirmwareEnabled) {
    Write-Host '[OK] La virtualisation est exposée à Windows.'
} else {
    Write-Warning "La virtualisation matérielle ne semble pas exposée à Windows. Si Windows est lui-même une VM, activez la virtualisation imbriquée dans l'hyperviseur hôte."
}

if ($NoVagrantUp) {
    Write-Host "`nPréparation terminée. Lancez plus tard : vagrant up" -ForegroundColor Green
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    exit
}

if (-not $vagrant -or -not (Test-Path $vagrant)) {
    $vagrant = $vagrantCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $vagrantCommand = Get-Command vagrant.exe -ErrorAction SilentlyContinue
    if (-not $vagrant -and -not $vagrantCommand) {
        throw 'Vagrant est installé mais son exécutable reste introuvable. Redémarrez Windows, puis relancez ce script.'
    }
    if (-not $vagrant) {
        $vagrant = $vagrantCommand.Source
    }
}

Write-Step 'Démarrage séquentiel du cluster Vagrant'
Push-Location $PSScriptRoot
try {
    # Le démarrage séquentiel limite la pression exercée sur un hyperviseur
    # imbriqué et facilite l'identification de la VM qui échoue.
    foreach ($machine in @('master', 'worker1', 'worker2')) {
        Write-Step "Démarrage de $machine"
        & $vagrant up $machine
        if ($LASTEXITCODE -ne 0) {
            throw "vagrant up $machine a échoué. Si VirtualBox vient d'être installé, redémarrez Windows puis relancez le script."
        }
    }

    Write-Host "`nCluster démarré. Vérification :" -ForegroundColor Green
    & $vagrant status
    Write-Host "`nÉtape suivante :" -ForegroundColor Yellow
    Write-Host 'vagrant ssh master -c "sudo bash /vagrant/scripts/storage.sh 192.168.56.10"'
} finally {
    Pop-Location
}

try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
