#!/bin/bash

# Git Sync Tool for Bash
# Синхронизация локального репозитория с удаленной копией и копирование в другой репозиторий

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для логирования
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"
}

# Проверка наличия git
check_git() {
    if ! command -v git &> /dev/null; then
        error "Git не установлен. Пожалуйста, установите git."
    else
        success "Git найден: $(git --version)"
    fi
}

# Проверка пути
check_path() {
    local path=$1
    local description=$2
    
    if [ -z "$path" ]; then
        error "Путь для $description не указан"
    fi
    
    if [ ! -d "$path" ]; then
        error "Директория $description не существует: $path"
    fi
    
    if [ ! -d "$path/.git" ]; then
        warning "Директория $description не является git-репозиторием (отсутствует папка .git)"
    fi
    
    log "✅ Путь проверен: $description = $path"
    return 0
}

# Основная функция синхронизации
sync_repositories() {
    local source_repo=$1
    local target_repo=$2
    local do_push=${3:-false}
    
    log "Начало синхронизации..."
    log "Исходный репозиторий: $source_repo"
    log "Целевой репозиторий: $target_repo"
    
    # Переходим в исходный репозиторий
    cd "$source_repo" || error "Не удалось перейти в исходный репозиторий"
    
    # Сохраняем текущую ветку
    local current_branch=$(git branch --show-current)
    log "Текущая ветка: $current_branch"
    
    # Проверяем наличие удаленного репозитория
    if git remote -v | grep -q "origin"; then
        log "Удаленный репозиторий (origin) найден"
        
        # Проверяем, приватный ли репозиторий (опционально)
        if git remote get-url origin | grep -q "github.com.*private"; then
            warning "Обнаружен приватный репозиторий. Убедитесь, что у вас есть доступ."
        fi
        
        # Git pull
        log "Выполняем git pull..."
        if git pull origin "$current_branch"; then
            success "Git pull выполнен успешно"
        else
            error "Ошибка при выполнении git pull. Проверьте подключение и права доступа."
        fi
    else
        warning "Удаленный репозиторий (origin) не настроен. Пропускаем git pull."
    fi
    
    # Копирование содержимого в целевой репозиторий (исключая .git)
    log "Копирование файлов в целевой репозиторий..."
    
    # Используем rsync если доступен, иначе cp
    if command -v rsync &> /dev/null; then
        log "Используем rsync для копирования..."
        rsync -av --delete --exclude='.git' "$source_repo/" "$target_repo/"
    else
        log "rsync не найден, используем cp..."
        # Альтернатива с cp
        # Сначала очищаем целевую директорию (кроме .git)
        find "$target_repo" -mindepth 1 -not -path "$target_repo/.git*" -delete 2>/dev/null
        # Копируем все кроме .git
        cp -r "$source_repo"/. "$target_repo/" 2>/dev/null
        # Удаляем .git если скопировался
        rm -rf "$target_repo/.git" 2>/dev/null
    fi
    
    success "Файлы скопированы успешно"
    
    # Опциональный git push
    if [ "$do_push" = true ]; then
        log "Выполняем git push в целевом репозитории..."
        cd "$target_repo" || error "Не удалось перейти в целевой репозиторий"
        
        if git status --porcelain | grep -q .; then
            git add .
            git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"
            if git push; then
                success "Git push выполнен успешно"
            else
                error "Ошибка при выполнении git push"
            fi
        else
            log "Нет изменений для коммита"
        fi
    fi
    
    success "Синхронизация завершена!"
}

# Интерактивный ввод или чтение из конфига
interactive_mode() {
    echo "========================================="
    echo "    Git Sync Tool - Интерактивный режим"
    echo "========================================="
    
    # Проверяем наличие конфигурационного файла
    local config_file="./config/settings.conf"
    local source_repo=""
    local target_repo=""
    local do_push=""
    
    # Функция для чтения конфига
read_config() {
    local config_file=$1
    
    if [ -f "$config_file" ]; then
        log "Найден конфигурационный файл: $config_file"
        
        # Читаем файл построчно
        while IFS='=' read -r key value || [ -n "$key" ]; do
            # Пропускаем комментарии и пустые строки
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z $key ]] && continue
            
            # Удаляем пробелы
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Присваиваем значения
            case "$key" in
                source_repo)
                    source_repo="$value"
                    log "Загружено: source_repo = $value"
                    ;;
                target_repo)
                    target_repo="$value"
                    log "Загружено: target_repo = $value"
                    ;;
                do_push)
                    do_push="$value"
                    log "Загружено: do_push = $value"
                    ;;
            esac
        done < "$config_file"
    fi
}

# Используйте функцию вместо source
read_config "$config_file"

    
    # Запрашиваем пути если не определены
    if [ -z "$source_repo" ]; then
        read -p "Введите путь к исходному репозиторию: " source_repo
    fi
    
    if [ -z "$target_repo" ]; then
        read -p "Введите путь к целевому репозиторию: " target_repo
    fi
    
    if [ -z "$do_push" ]; then
        read -p "Выполнить git push в целевом репозитории? (y/n): " push_choice
        if [[ "$push_choice" =~ ^[YyДд] ]]; then
            do_push=true
        else
            do_push=false
        fi
    fi
    
    # Проверка путей
    check_path "$source_repo" "исходный репозиторий"
    check_path "$target_repo" "целевой репозиторий"
    
    # Выполняем синхронизацию
    sync_repositories "$source_repo" "$target_repo" "$do_push"
}

# Автоматический запуск в новом окне терминала
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Проверка на запуск в отдельном окне
    if [ -z "$SYNC_TOOL_RUNNING" ] && [ -n "$DISPLAY" ]; then
        export SYNC_TOOL_RUNNING=1
        # Запуск в новом окне терминала (для Linux с GNOME)
        if command -v gnome-terminal &> /dev/null; then
            gnome-terminal -- bash -c "$0 $*; echo 'Нажмите Enter для закрытия...'; read"
            exit 0
        elif command -v xterm &> /dev/null; then
            xterm -e "$0 $*; echo 'Нажмите Enter для закрытия...'; read"
            exit 0
        fi
    fi
    
    # Основной запуск
    clear
    check_git
    echo ""
    
    # Обработка аргументов командной строки
    if [ $# -eq 2 ]; then
        # Прямой вызов с путями
        check_path "$1" "исходный репозиторий"
        check_path "$2" "целевой репозиторий"
        sync_repositories "$1" "$2" false
    elif [ $# -eq 3 ] && [ "$3" = "--push" ]; then
        # С опцией push
        check_path "$1" "исходный репозиторий"
        check_path "$2" "целевой репозиторий"
        sync_repositories "$1" "$2" true
    else
        # Интерактивный режим
        interactive_mode
    fi
    
    echo ""
    echo "Нажмите Enter для выхода..."
    read -r
fi