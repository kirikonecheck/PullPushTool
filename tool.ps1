#!/usr/bin/env pwsh
# Git Sync Tool for PowerShell
# Синхронизация локального репозитория с удаленной копией

<#
.SYNOPSIS
    Скрипт для синхронизации git репозиториев
.DESCRIPTION
    Выполняет git pull в исходном репозитории и копирует все файлы (кроме .git) в целевой репозиторий
.EXAMPLE
    .\sync_repo.ps1 -SourceRepo "C:\Users\mamae\Desktop\Programming\mfua" -TargetRepo "C:\Users\mamae\Desktop\Programming\mfua-backup"
.EXAMPLE
    .\sync_repo.ps1 -ConfigFile "config\settings.conf"
#>

param(
    [string]$SourceRepo,
    [string]$TargetRepo,
    [switch]$Push,
    [string]$ConfigFile = ".\settings.conf"
)

# Цвета для вывода
$Host.UI.RawUI.ForegroundColor = "White"
$script:ErrorActionPreference = "Stop"

# Функции для красивого вывода
function Write-Log {
    param([string]$Message, [string]$Color = "Cyan")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { Write-Log $args[0] -Color "Green" }
function Write-Warning { Write-Log $args[0] -Color "Yellow" }
function Write-ErrorMsg { Write-Log $args[0] -Color "Red" }

# Проверка наличия git
function Test-Git {
    try {
        $gitVersion = git --version
        Write-Success "Git найден: $gitVersion"
        return $true
    }
    catch {
        Write-ErrorMsg "Git не установлен. Скачайте с https://git-scm.com/"
        return $false
    }
}

# Проверка пути
function Test-RepositoryPath {
    param([string]$Path, [string]$Description)
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-ErrorMsg "Путь для $Description не указан"
        return $false
    }
    
    # Пробуем разные варианты пути
    $resolvedPath = $Path
    if (-not (Test-Path $resolvedPath)) {
        # Пробуем заменить / на \
        $resolvedPath = $Path -replace '/', '\'
        Write-Warning "Пробуем альтернативный путь: $resolvedPath"
    }
    
    if (-not (Test-Path $resolvedPath)) {
        Write-ErrorMsg "Директория $Description не существует: $Path"
        Write-Host "    Проверьте путь: $resolvedPath" -ForegroundColor Gray
        return $false
    }
    
    if (-not (Test-Path "$resolvedPath\.git")) {
        Write-Warning "Директория $Description не является git-репозиторием (отсутствует папка .git)"
    }
    
    # Возвращаем правильный путь
    return $resolvedPath
}

# Чтение конфигурации
function Read-Config {
    param([string]$ConfigPath)
    
    $config = @{
        source_repo = ""
        target_repo = ""
        do_push = "false"
    }
    
    if (Test-Path $ConfigPath) {
        Write-Log "Найден конфигурационный файл: $ConfigPath"
        
        Get-Content $ConfigPath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $parts = $line -split '=', 2
                if ($parts.Count -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    $config[$key] = $value
                    Write-Log "  → $key = $value" -Color "Gray"
                }
            }
        }
    }
    else {
        Write-Warning "Конфигурационный файл не найден: $ConfigPath"
    }
    
    return $config
}

# Основная функция синхронизации
function Sync-Repositories {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [bool]$DoPush
    )
    
    Write-Host "`n" + "="*50 -ForegroundColor Cyan
    Write-Host "    НАЧАЛО СИНХРОНИЗАЦИИ" -ForegroundColor Cyan
    Write-Host "="*50 -ForegroundColor Cyan
    
    Write-Log "Исходный репозиторий: $SourcePath"
    Write-Log "Целевой репозиторий: $TargetPath"
    Write-Log "Выполнить push: $DoPush"
    
    # Сохраняем текущую директорию
    $originalLocation = Get-Location
    
    try {
        # Шаг 1: Git pull в исходном репозитории
        Write-Host "`n--- ШАГ 1: Git pull ---" -ForegroundColor Yellow
        Set-Location $SourcePath
        
        $currentBranch = git branch --show-current
        if (-not $currentBranch) {
            $currentBranch = "main"
            Write-Warning "Не удалось определить ветку, используем 'main'"
        }
        Write-Log "Текущая ветка: $currentBranch"
        
        $remoteExists = git remote | Select-String "origin"
        if ($remoteExists) {
            Write-Log "Выполняем git pull origin $currentBranch..."
            
            $pullResult = git pull origin $currentBranch 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Git pull выполнен успешно"
            }
            else {
                Write-ErrorMsg "Ошибка git pull: $pullResult"
                throw "Git pull failed"
            }
        }
        else {
            Write-Warning "Удаленный репозиторий 'origin' не настроен. Пропускаем git pull."
        }
        
        # Шаг 2: Копирование файлов
        Write-Host "`n--- ШАГ 2: Копирование файлов ---" -ForegroundColor Yellow
        Write-Log "Копируем файлы из исходного репозитория (исключая .git)..."
        
        # Проверяем существование целевой папки
        if (-not (Test-Path $TargetPath)) {
            New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
            Write-Log "Создана целевая папка: $TargetPath"
        }
        
        # Получаем все файлы и папки, исключая .git
        $items = Get-ChildItem -Path $SourcePath -Exclude ".git"
        $fileCount = 0
        
        foreach ($item in $items) {
            $destPath = Join-Path $TargetPath $item.Name
            
            if ($item.PSIsContainer) {
                # Копируем папки
                Copy-Item -Path $item.FullName -Destination $destPath -Recurse -Force
                Write-Log "  📁 Папка: $($item.Name)" -Color "Gray"
            }
            else {
                # Копируем файлы
                Copy-Item -Path $item.FullName -Destination $destPath -Force
                $fileCount++
            }
        }
        
        # Удаляем файлы в целевой папке, которых нет в исходной
        $targetItems = Get-ChildItem -Path $TargetPath -Exclude ".git"
        foreach ($targetItem in $targetItems) {
            $sourcePathItem = Join-Path $SourcePath $targetItem.Name
            if (-not (Test-Path $sourcePathItem)) {
                Remove-Item -Path $targetItem.FullName -Recurse -Force
                Write-Log "  🗑️ Удалено: $($targetItem.Name)" -Color "Gray"
            }
        }
        
        Write-Success "Скопировано $fileCount файлов"
        
        # Шаг 3: Опциональный git push
        if ($DoPush) {
            Write-Host "`n--- ШАГ 3: Git push ---" -ForegroundColor Yellow
            Set-Location $TargetPath
            
            $status = git status --porcelain
            if ($status) {
                Write-Log "Обнаружены изменения, выполняем commit и push..."
                
                git add .
                git commit -m "Auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                
                $pushResult = git push 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Git push выполнен успешно"
                }
                else {
                    Write-ErrorMsg "Ошибка git push: $pushResult"
                }
            }
            else {
                Write-Log "Нет изменений для коммита"
            }
        }
        
        Write-Host "`n" + "="*50 -ForegroundColor Green
        Write-Success "СИНХРОНИЗАЦИЯ ЗАВЕРШЕНА УСПЕШНО!"
        Write-Host "="*50 -ForegroundColor Green
    }
    catch {
        Write-ErrorMsg "Ошибка: $_"
        Write-Host "="*50 -ForegroundColor Red
    }
    finally {
        # Возвращаемся в исходную директорию
        Set-Location $originalLocation
    }
}

# Интерактивный режим
function Start-InteractiveMode {
    Clear-Host
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "      GIT SYNC TOOL - ИНТЕРАКТИВНЫЙ РЕЖИМ" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Читаем конфигурацию
    $config = Read-Config -ConfigPath $ConfigFile
    
    # Запрашиваем пути
    $sourceRepo = if ($config['source_repo']) { $config['source_repo'] } else { $SourceRepo }
    $targetRepo = if ($config['target_repo']) { $config['target_repo'] } else { $TargetRepo }
    $doPush = if ($config['do_push'] -eq 'true') { $true } else { $false }
    
    if ([string]::IsNullOrWhiteSpace($sourceRepo)) {
        $sourceRepo = Read-Host "Введите путь к исходному репозиторию`n(например: C:\Users\mamae\Desktop\Programming\mfua)"
    }
    
    if ([string]::IsNullOrWhiteSpace($targetRepo)) {
        $targetRepo = Read-Host "`nВведите путь к целевому репозиторию`n(например: C:\Users\mamae\Desktop\Programming\mfua-backup)"
    }
    
    if (-not $PSBoundParameters.ContainsKey('Push') -and -not $config.ContainsKey('do_push')) {
        $pushChoice = Read-Host "`nВыполнить git push в целевом репозитории? (y/n)"
        $doPush = $pushChoice -match '^[YyДд]'
    }
    
    # Проверка путей
    $validSource = Test-RepositoryPath -Path $sourceRepo -Description "исходный репозиторий"
    $validTarget = Test-RepositoryPath -Path $targetRepo -Description "целевой репозиторий"
    
    if ($validSource -and $validTarget) {
        Sync-Repositories -SourcePath $validSource -TargetPath $validTarget -DoPush $doPush
    }
    else {
        Write-ErrorMsg "Проверьте правильность путей"
    }
}

# Основная логика
Clear-Host

# Проверка git
if (-not (Test-Git)) {
    Read-Host "`nНажмите Enter для выхода"
    exit 1
}

# Запуск
if ($SourceRepo -and $TargetRepo) {
    # Прямой вызов с параметрами
    $validSource = Test-RepositoryPath -Path $SourceRepo -Description "исходный репозиторий"
    $validTarget = Test-RepositoryPath -Path $TargetRepo -Description "целевой репозиторий"
    
    if ($validSource -and $validTarget) {
        Sync-Repositories -SourcePath $validSource -TargetPath $validTarget -DoPush $Push
    }
}
else {
    # Интерактивный режим
    Start-InteractiveMode
}

Read-Host "`nНажмите Enter для выхода"