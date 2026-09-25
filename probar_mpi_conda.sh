#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# CLUSTER MPI CON CONDA/MINIFORGE
# Compatible con:
#   - Ubuntu / Debian
#   - Arch / Manjaro / EndeavourOS
#   - Fedora
#
# NO ejecutar con:
#   sudo ./probar_mpi_conda.sh
#
# Ejecutar como:
#   ./probar_mpi_conda.sh
# ============================================================


MINIFORGE_DIR="/opt/miniforge3"
MPI_ENV="/opt/mpi-env"
PROJECT_DIR="$HOME/prueba_mpi"


# ============================================================
# COLORES
# ============================================================

VERDE="\033[0;32m"
AMARILLO="\033[1;33m"
ROJO="\033[0;31m"
RESET="\033[0m"


# ============================================================
# FUNCIONES
# ============================================================

info() {
    echo -e "${VERDE}$1${RESET}"
}

advertencia() {
    echo -e "${AMARILLO}$1${RESET}"
}

error() {
    echo -e "${ROJO}$1${RESET}"
}


# ============================================================
# COMPROBAR USUARIO
# ============================================================

if [ "$EUID" -eq 0 ]; then
    error "ERROR: No ejecutes todo el script con sudo."
    echo
    echo "Ejecuta:"
    echo
    echo "    ./probar_mpi_conda.sh"
    echo
    exit 1
fi


echo "=========================================================="
echo " CONFIGURACION LOCAL - CONDA + OPENMPI"
echo "=========================================================="
echo


# ============================================================
# 1. INFORMACION DEL SISTEMA
# ============================================================

info "[1/8] Información del sistema"

HOSTNAME_NODO="$(uname -n)"
ARQUITECTURA="$(uname -m)"
KERNEL="$(uname -s)"

echo "Hostname:     $HOSTNAME_NODO"
echo "Kernel:       $KERNEL"
echo "Arquitectura: $ARQUITECTURA"

if [ -f /etc/os-release ]; then

    . /etc/os-release

    echo "Distribución: ${PRETTY_NAME:-desconocida}"

fi

echo


# ============================================================
# 2. INSTALAR DEPENDENCIAS
# ============================================================

info "[2/8] Instalando dependencias del sistema"


# ------------------------------------------------------------
# UBUNTU / DEBIAN
# ------------------------------------------------------------

if command -v apt-get >/dev/null 2>&1; then

    echo "Sistema basado en Debian/Ubuntu detectado."
    echo

    if ! sudo apt-get update; then

        advertencia "apt update falló."

        # Solo hacemos este cambio automático si realmente es Ubuntu.
        if [ "${ID:-}" = "ubuntu" ]; then

            advertencia "Intentando cambiar mirror regional de Ubuntu..."

            BACKUP_DIR="/etc/apt/cluster-backup"

            sudo mkdir -p "$BACKUP_DIR"

            # Copiar configuraciones como respaldo
            if [ -f /etc/apt/sources.list ]; then

                sudo cp \
                    /etc/apt/sources.list \
                    "$BACKUP_DIR/sources.list" \
                    2>/dev/null || true

            fi


            if [ -d /etc/apt/sources.list.d ]; then

                sudo cp \
                    /etc/apt/sources.list.d/*.sources \
                    "$BACKUP_DIR/" \
                    2>/dev/null || true

                sudo cp \
                    /etc/apt/sources.list.d/*.list \
                    "$BACKUP_DIR/" \
                    2>/dev/null || true

            fi


            echo
            echo "Cambiando mirrors *.archive.ubuntu.com"
            echo "a archive.ubuntu.com..."
            echo


            # sources.list antiguo
            if [ -f /etc/apt/sources.list ]; then

                sudo sed -Ei \
                    's|https?://[a-zA-Z0-9.-]+\.archive\.ubuntu\.com/ubuntu/?|http://archive.ubuntu.com/ubuntu/|g' \
                    /etc/apt/sources.list

            fi


            # Formato nuevo .sources
            for archivo in /etc/apt/sources.list.d/*.sources; do

                [ -e "$archivo" ] || continue

                sudo sed -Ei \
                    's|https?://[a-zA-Z0-9.-]+\.archive\.ubuntu\.com/ubuntu/?|http://archive.ubuntu.com/ubuntu/|g' \
                    "$archivo"

            done


            # Formato .list
            for archivo in /etc/apt/sources.list.d/*.list; do

                [ -e "$archivo" ] || continue

                sudo sed -Ei \
                    's|https?://[a-zA-Z0-9.-]+\.archive\.ubuntu\.com/ubuntu/?|http://archive.ubuntu.com/ubuntu/|g' \
                    "$archivo"

            done


            echo "Limpiando listas antiguas..."

            sudo rm -rf /var/lib/apt/lists/*


            echo "Reintentando apt update..."

            sudo apt-get update

        else

            error "apt update falló y el sistema no parece ser Ubuntu."
            exit 1

        fi

    fi


    sudo apt-get install -y \
        curl \
        ca-certificates \
        openssh-server \
        iproute2


# ------------------------------------------------------------
# ARCH
# ------------------------------------------------------------

elif command -v pacman >/dev/null 2>&1; then

    echo "Sistema Arch/Manjaro/EndeavourOS detectado."

    sudo pacman -Sy \
        --needed \
        --noconfirm \
        curl \
        ca-certificates \
        openssh \
        iproute2


# ------------------------------------------------------------
# FEDORA
# ------------------------------------------------------------

elif command -v dnf >/dev/null 2>&1; then

    echo "Sistema Fedora detectado."

    sudo dnf install -y \
        curl \
        ca-certificates \
        openssh-server \
        iproute


else

    error "ERROR: No reconozco el gestor de paquetes."

    echo
    echo "Actualmente soportados:"
    echo
    echo "  apt     -> Ubuntu / Debian"
    echo "  pacman  -> Arch / Manjaro"
    echo "  dnf     -> Fedora"

    exit 1

fi


echo


# ============================================================
# 3. CONFIGURAR SSH
# ============================================================

info "[3/8] Configurando SSH"


if command -v systemctl >/dev/null 2>&1; then

    if systemctl list-unit-files 2>/dev/null |
        grep -q '^ssh.service'; then

        sudo systemctl enable --now ssh

        echo "Servicio ssh activado."


    elif systemctl list-unit-files 2>/dev/null |
        grep -q '^sshd.service'; then

        sudo systemctl enable --now sshd

        echo "Servicio sshd activado."

    else

        advertencia "No encontré ssh.service ni sshd.service."
        advertencia "La prueba local MPI puede continuar."

    fi

else

    advertencia "systemctl no está disponible."
    advertencia "La prueba local puede continuar."

fi


echo


# ============================================================
# 4. INSTALAR MINIFORGE
# ============================================================

info "[4/8] Comprobando Miniforge"


if [ ! -x "$MINIFORGE_DIR/bin/conda" ]; then

    echo "Miniforge no está instalado."
    echo


    case "$ARQUITECTURA" in

        x86_64)

            MINIFORGE_ARCH="x86_64"

            ;;


        aarch64|arm64)

            MINIFORGE_ARCH="aarch64"

            ;;


        ppc64le)

            MINIFORGE_ARCH="ppc64le"

            ;;


        *)

            error "Arquitectura no soportada automáticamente:"
            echo "$ARQUITECTURA"

            exit 1

            ;;

    esac


    INSTALLER="/tmp/miniforge_cluster.sh"


    echo "Descargando Miniforge..."


    curl \
        -L \
        --fail \
        --retry 3 \
        --retry-delay 2 \
        "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${MINIFORGE_ARCH}.sh" \
        -o "$INSTALLER"


    echo
    echo "Instalando Miniforge en:"
    echo
    echo "    $MINIFORGE_DIR"
    echo


    sudo bash "$INSTALLER" \
        -b \
        -p "$MINIFORGE_DIR"


    rm -f "$INSTALLER"


    # Permitir que el usuario actual gestione Miniforge
    sudo chown -R \
        "$USER":"$(id -gn)" \
        "$MINIFORGE_DIR"


else

    echo "Miniforge ya está instalado."

fi


CONDA="$MINIFORGE_DIR/bin/conda"


echo


# ============================================================
# 5. CREAR ENTORNO MPI
# ============================================================

info "[5/8] Configurando entorno MPI"


if [ ! -x "$MPI_ENV/bin/mpirun" ]; then

    echo
    echo "Creando entorno MPI en:"
    echo
    echo "    $MPI_ENV"
    echo


    sudo mkdir -p "$MPI_ENV"


    sudo chown -R \
        "$USER":"$(id -gn)" \
        "$MPI_ENV"


    "$CONDA" create \
        --prefix "$MPI_ENV" \
        --override-channels \
        -c conda-forge \
        openmpi \
        openmpi-mpicc \
        c-compiler \
        cxx-compiler \
        -y


else

    echo "El entorno MPI ya existe."

fi


echo


# ============================================================
# 6. ACTIVAR CORRECTAMENTE EL ENTORNO
# ============================================================

info "[6/8] Activando rutas del entorno MPI"


# ESTA ES LA PARTE QUE FALTABA EN EL SCRIPT ANTERIOR
export PATH="$MPI_ENV/bin:$PATH"

export LD_LIBRARY_PATH="$MPI_ENV/lib:${LD_LIBRARY_PATH:-}"


# También indicamos explícitamente el prefijo Conda
export CONDA_PREFIX="$MPI_ENV"


echo
echo "PATH MPI:"
echo
echo "    $MPI_ENV/bin"
echo


# ============================================================
# COMPROBAR EJECUTABLES
# ============================================================

if ! command -v mpirun >/dev/null 2>&1; then

    error "ERROR: mpirun no fue encontrado."

    exit 1

fi


if ! command -v mpicc >/dev/null 2>&1; then

    error "ERROR: mpicc no fue encontrado."

    echo
    echo "Intentando instalar openmpi-mpicc..."
    echo


    "$CONDA" install \
        --prefix "$MPI_ENV" \
        --override-channels \
        -c conda-forge \
        openmpi-mpicc \
        -y


    export PATH="$MPI_ENV/bin:$PATH"

fi


echo "mpirun:"
echo "    $(command -v mpirun)"

echo

echo "mpicc:"
echo "    $(command -v mpicc)"

echo


# ============================================================
# COMPROBAR COMPILADOR REAL DE CONDA
# ============================================================

echo "Comprobando compilador usado por mpicc..."


COMPILADOR_MPI="$(mpicc --showme:command 2>/dev/null || true)"


echo
echo "Compilador:"
echo
echo "    $COMPILADOR_MPI"
echo


# Verificar que realmente exista
COMPILADOR_BINARIO="$(echo "$COMPILADOR_MPI" | awk '{print $1}')"


if [ -n "$COMPILADOR_BINARIO" ]; then

    if command -v "$COMPILADOR_BINARIO" >/dev/null 2>&1; then

        echo "Compilador encontrado:"
        echo
        echo "    $(command -v "$COMPILADOR_BINARIO")"

    else

        error "ERROR: El compilador configurado por MPI no se encuentra."

        echo
        echo "Contenido relevante de:"
        echo
        echo "    $MPI_ENV/bin"
        echo

        ls "$MPI_ENV/bin" |
            grep -E 'gcc|g\+\+|conda-linux' |
            head -n 30 || true

        exit 1

    fi

fi


echo


# ============================================================
# 7. CREAR PROGRAMA MPI
# ============================================================

info "[7/8] Creando y compilando programa MPI"


mkdir -p "$PROJECT_DIR"


cat > "$PROJECT_DIR/hola.c" << 'EOF'
#include <mpi.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    int rank;
    int size;

    char nombre[MPI_MAX_PROCESSOR_NAME];
    int longitud;

    MPI_Init(&argc, &argv);

    MPI_Comm_rank(
        MPI_COMM_WORLD,
        &rank
    );

    MPI_Comm_size(
        MPI_COMM_WORLD,
        &size
    );

    MPI_Get_processor_name(
        nombre,
        &longitud
    );

    printf(
        "Hola desde %-15s | proceso %d de %d\n",
        nombre,
        rank,
        size
    );

    fflush(stdout);

    MPI_Finalize();

    return 0;
}
EOF


echo
echo "Código creado:"
echo
echo "    $PROJECT_DIR/hola.c"
echo


echo "Compilando..."
echo


mpicc \
    "$PROJECT_DIR/hola.c" \
    -o "$PROJECT_DIR/hola"


if [ ! -x "$PROJECT_DIR/hola" ]; then

    error "ERROR: El ejecutable no fue creado."

    exit 1

fi


echo
echo "Compilación correcta."
echo


# ============================================================
# 8. PRUEBA MPI
# ============================================================

info "[8/8] Ejecutando prueba MPI local"


NUM_CPU="$(nproc 2>/dev/null || echo 2)"


# Para prueba inicial usamos máximo 4 procesos
if [ "$NUM_CPU" -ge 4 ]; then

    PROCESOS=4

else

    PROCESOS="$NUM_CPU"

fi


echo
echo "Procesadores detectados: $NUM_CPU"
echo "Procesos MPI utilizados: $PROCESOS"
echo


mpirun \
    -np "$PROCESOS" \
    "$PROJECT_DIR/hola"


# ============================================================
# RESULTADO
# ============================================================

echo
echo
echo "=========================================================="
echo " CONFIGURACION COMPLETADA CORRECTAMENTE"
echo "=========================================================="
echo


echo "Hostname:"
echo
echo "    $(uname -n)"
echo


echo "Arquitectura:"
echo
echo "    $(uname -m)"
echo


echo "CPU disponibles:"
echo
echo "    $NUM_CPU"
echo


echo "OpenMPI:"
echo

mpirun --version |
    head -n 2


echo
echo "Compilador MPI:"
echo
echo "    $(mpicc --showme:command 2>/dev/null || echo desconocido)"
echo


echo "Entorno MPI:"
echo
echo "    $MPI_ENV"
echo


echo "Programa:"
echo
echo "    $PROJECT_DIR/hola"
echo


echo "Interfaces de red:"
echo

if command -v ip >/dev/null 2>&1; then

    ip -br addr

else

    echo "Comando ip no encontrado."

fi


echo
echo "=========================================================="
echo " PARA EJECUTAR NUEVAMENTE"
echo "=========================================================="
echo

echo "export PATH=\"$MPI_ENV/bin:\$PATH\""
echo "export LD_LIBRARY_PATH=\"$MPI_ENV/lib:\${LD_LIBRARY_PATH:-}\""

echo

echo "mpirun -np $PROCESOS $PROJECT_DIR/hola"

echo
echo "=========================================================="