#!/bin/bash
# ==========================================================
#  rayos-x.sh - Hace una "radiografía" rápida del equipo
#  Autora: Bea García (bgarciaa181)
#  Uso: ./rayos-x.sh        -> muestra el informe
#       ./rayos-x.sh -g     -> muestra y guarda el informe en un .txt
#       ./rayos-x.sh -w     -> genera un informe en HTML (panel web)
#       ./rayos-x.sh -l     -> modo en vivo (se actualiza cada segundo)
#       ./rayos-x.sh -h     -> muestra la ayuda
# ==========================================================

# ---------- Colores ----------
ROJO=$'\e[31m'
VERDE=$'\e[32m'
AMARILLO=$'\e[33m'
AZUL=$'\e[34m'
CIAN=$'\e[36m'
NEGRITA=$'\e[1m'
NORMAL=$'\e[0m'

# Lista donde vamos guardando los avisos que salgan
AVISOS=()

# ==========================================================
#  FUNCIONES DE AYUDA Y DIBUJO
# ==========================================================

ayuda() {
    echo "Uso: $0 [opción]"
    echo "  (sin opción)  Muestra el informe del sistema"
    echo "  -g            Muestra el informe y lo guarda en un .txt"
    echo "  -w            Genera un informe en HTML para abrir en el navegador"
    echo "  -l            Modo en vivo: CPU, RAM y disco cada segundo"
    echo "  -h            Muestra esta ayuda"
}

banner() {
    echo "${CIAN}${NEGRITA}"
    echo "  ____                            __  __"
    echo " |  _ \ __ _ _   _  ___  ___      \ \/ /"
    echo " | |_) / _\` | | | |/ _ \/ __|_____\  / "
    echo " |  _ < (_| | |_| | (_) \__ \_____/  \ "
    echo " |_| \_\__,_|\__, |\___/|___/    /_/\_\\"
    echo "             |___/   Radiografía del sistema"
    echo "${NORMAL}"
    echo " Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
}

titulo() {
    echo
    echo "${AZUL}${NEGRITA}== $1 ==${NORMAL}"
}

# Devuelve el color de terminal según el porcentaje
color_segun() {
    if [ "$1" -ge 90 ]; then
        echo "$ROJO"
    elif [ "$1" -ge 70 ]; then
        echo "$AMARILLO"
    else
        echo "$VERDE"
    fi
}

# Lo mismo pero en color web (para el HTML)
color_html() {
    if [ "$1" -ge 90 ]; then
        echo "#ef4444"
    elif [ "$1" -ge 70 ]; then
        echo "#eab308"
    else
        echo "#22c55e"
    fi
}

# Dibuja una barra de 20 bloques según el porcentaje
barra() {
    porcentaje=$1
    llenos=$((porcentaje / 5))
    vacios=$((20 - llenos))
    color=$(color_segun "$porcentaje")

    printf "%s[" "$color"
    for ((i = 0; i < llenos; i++)); do printf "#"; done
    for ((i = 0; i < vacios; i++)); do printf "."; done
    printf "] %3d%%%s\n" "$porcentaje" "$NORMAL"
}

# ==========================================================
#  FUNCIONES QUE RECOGEN DATOS
# ==========================================================

# Calcula el uso de CPU leyendo /proc/stat dos veces con 1 segundo de diferencia
uso_cpu() {
    read -r _ u1 n1 s1 i1 w1 x1 y1 z1 _ < /proc/stat
    sleep 1
    read -r _ u2 n2 s2 i2 w2 x2 y2 z2 _ < /proc/stat

    total=$(( (u2 + n2 + s2 + i2 + w2 + x2 + y2 + z2) - (u1 + n1 + s1 + i1 + w1 + x1 + y1 + z1) ))
    libre=$(( (i2 + w2) - (i1 + w1) ))

    if [ "$total" -eq 0 ]; then
        echo 0
    else
        echo $(( (total - libre) * 100 / total ))
    fi
}

uso_ram() {
    free -m | awk '/Mem:/ {print int(($2 - $7) * 100 / $2)}'
}

uso_disco() {
    df / | awk 'NR==2 {print $5}' | tr -d '%'
}

# Si el porcentaje pasa del 90% añade un aviso a la lista
comprobar() {
    if [ "$2" -ge 90 ]; then
        AVISOS+=("$1 está al $2%")
    fi
}

# Recoge todos los datos del equipo y los guarda en variables
recoger_datos() {
    . /etc/os-release

    # Equipo
    NOMBRE=$(hostname)
    USUARIO=$(whoami)
    SISTEMA=$PRETTY_NAME
    KERNEL=$(uname -r)
    ENCENDIDO=$(uptime -p | sed 's/up //')

    # CPU
    MODELO=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
    MODELO=${MODELO:-desconocido}
    NUCLEOS=$(nproc)
    CPU=$(uso_cpu)

    # RAM
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USADA=$(free -m | awk '/Mem:/ {print $2 - $7}')
    RAM_PCT=$(uso_ram)

    # Disco
    DISCO_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISCO_USADO=$(df -h / | awk 'NR==2 {print $3}')
    DISCO_PCT=$(uso_disco)

    # Red
    # Las IPs se tapan: solo se ven los dos primeros números (ej: 10.209.*.*)
    IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}' | awk -F. '{print $1"."$2".*.*"}')
    IP_LOCAL=${IP_LOCAL:-sin IP}
    PUERTA=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}' | awk -F. '{print $1"."$2".*.*"}')
    PUERTA=${PUERTA:-no encontrada}
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        INTERNET="si"
    else
        INTERNET="no"
        AVISOS+=("No hay conexión a Internet")
    fi

    # Puertos escuchando
    if command -v ss > /dev/null; then
        # Solo puertos menores de 32768: los de arriba son temporales (navegador, etc.)
        PUERTOS=$(ss -tuln | awk 'NR>1 {n = split($5, a, ":"); if (a[n] < 32768) print $1 "/" a[n]}' | sort -t/ -k1,1 -k2n | uniq | tr '\n' ' ')
    else
        PUERTOS=""
    fi

    # Procesos y usuarios
    # El nombre va al final porque algunos tienen espacios (ej: "Isolated Web Co")
    PROCESOS=$(ps -eo pid,%mem,%cpu,comm --sort=-%mem | head -6)
    CONECTADOS=$(who)

    # Avisos por uso alto
    comprobar "La CPU" "$CPU"
    comprobar "La RAM" "$RAM_PCT"
    comprobar "El disco" "$DISCO_PCT"
}

# ==========================================================
#  INFORME EN TERMINAL
# ==========================================================

informe() {
    banner

    titulo "EQUIPO"
    echo " Nombre:        $NOMBRE"
    echo " Usuario:       $USUARIO"
    echo " Sistema:       $SISTEMA"
    echo " Kernel:        $KERNEL"
    echo " Encendido:     $ENCENDIDO"

    titulo "CPU"
    echo " Modelo:        $MODELO"
    echo " Núcleos:       $NUCLEOS"
    printf " Uso:           "
    barra "$CPU"

    titulo "MEMORIA RAM"
    echo " Usada:         ${RAM_USADA} MB de ${RAM_TOTAL} MB"
    printf " Uso:           "
    barra "$RAM_PCT"

    titulo "DISCO (/)"
    echo " Usado:         ${DISCO_USADO} de ${DISCO_TOTAL}"
    printf " Uso:           "
    barra "$DISCO_PCT"

    titulo "RED"
    echo " IP local:      $IP_LOCAL"
    echo " Puerta enlace: $PUERTA"
    if [ "$INTERNET" = "si" ]; then
        echo " Internet:      ${VERDE}conectado${NORMAL}"
    else
        echo " Internet:      ${ROJO}sin conexión${NORMAL}"
    fi

    titulo "PUERTOS ESCUCHANDO"
    echo " ${PUERTOS:-ninguno (o no está instalado ss)}"

    titulo "TOP 5 PROCESOS (por RAM)"
    echo "$PROCESOS" | sed 's/^/ /'

    titulo "USUARIOS CONECTADOS"
    echo " ${CONECTADOS:-ninguno}"

    titulo "RESUMEN"
    if [ ${#AVISOS[@]} -eq 0 ]; then
        echo " ${VERDE}${NEGRITA}Todo en orden, el equipo está sano :)${NORMAL}"
    else
        for aviso in "${AVISOS[@]}"; do
            echo " ${ROJO}[!] $aviso${NORMAL}"
        done
    fi
    echo
}

# ==========================================================
#  INFORME EN HTML
# ==========================================================

# Crea el trozo de HTML de un indicador circular
indicador() {
    nombre=$1
    porcentaje=$2
    detalle=$3
    color=$(color_html "$porcentaje")
    echo "<div class='tarjeta'>
        <h2>$nombre</h2>
        <div class='circulo' style='--p:$porcentaje; --c:$color'><span>$porcentaje%</span></div>
        <p class='detalle'>$detalle</p>
    </div>"
}

generar_html() {
    fichero="informe_${NOMBRE}_$(date '+%Y%m%d_%H%M').html"

    # Estado general arriba del todo
    if [ ${#AVISOS[@]} -eq 0 ]; then
        estado="<div class='estado ok'>✔ Todo en orden, el equipo está sano</div>"
    else
        estado="<div class='estado mal'>"
        for aviso in "${AVISOS[@]}"; do
            estado+="<div>⚠ $aviso</div>"
        done
        estado+="</div>"
    fi

    # Filas de la tabla de procesos (quitamos la cabecera de ps)
    filas=""
    while read -r pid mem cpu comando; do
        filas+="<tr><td>$pid</td><td>$comando</td><td>$mem%</td><td>$cpu%</td></tr>"
    done < <(echo "$PROCESOS" | sed 1d | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    # Puertos como etiquetas
    etiquetas=""
    for puerto in $PUERTOS; do
        etiquetas+="<span class='chip'>$puerto</span>"
    done
    etiquetas=${etiquetas:-<span class='gris'>ninguno</span>}

    if [ "$INTERNET" = "si" ]; then
        internet="<span class='verde'>● conectado</span>"
    else
        internet="<span class='rojo'>● sin conexión</span>"
    fi

    cat > "$fichero" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>rayos-x · $NOMBRE</title>
<style>
    body { margin: 0; background: #0b1120; color: #e2e8f0; font-family: Consolas, "Courier New", monospace; }
    .contenedor { max-width: 1000px; margin: 0 auto; padding: 24px 16px; }
    header h1 { margin: 0; color: #22d3ee; font-size: 2.2rem; letter-spacing: 2px; }
    header p { margin: 4px 0 20px; color: #94a3b8; }
    .estado { padding: 14px 18px; border-radius: 10px; margin-bottom: 20px; font-weight: bold; }
    .ok { background: #052e16; border: 1px solid #22c55e; color: #4ade80; }
    .mal { background: #2a0a0a; border: 1px solid #ef4444; color: #f87171; }
    .rejilla { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 16px; }
    .tarjeta { background: #111827; border: 1px solid #1f2937; border-radius: 12px; padding: 18px; }
    .tarjeta h2 { margin: 0 0 14px; font-size: 0.9rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; }
    .circulo { width: 130px; height: 130px; margin: 0 auto; border-radius: 50%;
               background: conic-gradient(var(--c) calc(var(--p) * 1%), #1f2937 0);
               display: grid; place-items: center; }
    .circulo span { width: 100px; height: 100px; border-radius: 50%; background: #111827;
                    display: grid; place-items: center; font-size: 1.6rem; font-weight: bold; }
    .detalle { text-align: center; color: #94a3b8; margin: 12px 0 0; }
    .dato { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #1f2937; gap: 12px; }
    .dato:last-child { border-bottom: none; }
    .dato b { color: #94a3b8; font-weight: normal; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 6px 4px; border-bottom: 1px solid #1f2937; }
    th { color: #94a3b8; font-weight: normal; }
    .chip { display: inline-block; background: #164e63; color: #67e8f9; padding: 4px 10px; border-radius: 20px; margin: 3px; font-size: 0.85rem; }
    .verde { color: #4ade80; } .rojo { color: #f87171; } .gris { color: #64748b; }
    footer { text-align: center; color: #475569; margin-top: 24px; font-size: 0.85rem; }
</style>
</head>
<body>
<div class="contenedor">

<header>
    <h1>RAYOS-X</h1>
    <p>Radiografía de <b>$NOMBRE</b> · $(date '+%d/%m/%Y %H:%M:%S')</p>
</header>

$estado

<div class="rejilla">
    $(indicador "CPU" "$CPU" "$NUCLEOS núcleos")
    $(indicador "Memoria RAM" "$RAM_PCT" "$RAM_USADA MB de $RAM_TOTAL MB")
    $(indicador "Disco (/)" "$DISCO_PCT" "$DISCO_USADO de $DISCO_TOTAL")
</div>

<div class="rejilla">
    <div class="tarjeta">
        <h2>Equipo</h2>
        <div class="dato"><b>Nombre</b><span>$NOMBRE</span></div>
        <div class="dato"><b>Usuario</b><span>$USUARIO</span></div>
        <div class="dato"><b>Sistema</b><span>$SISTEMA</span></div>
        <div class="dato"><b>Kernel</b><span>$KERNEL</span></div>
        <div class="dato"><b>Encendido</b><span>$ENCENDIDO</span></div>
        <div class="dato"><b>CPU</b><span>$MODELO</span></div>
    </div>
    <div class="tarjeta">
        <h2>Red</h2>
        <div class="dato"><b>IP local</b><span>$IP_LOCAL</span></div>
        <div class="dato"><b>Puerta de enlace</b><span>$PUERTA</span></div>
        <div class="dato"><b>Internet</b>$internet</div>
        <h2 style="margin-top:18px">Puertos escuchando</h2>
        $etiquetas
    </div>
</div>

<div class="tarjeta">
    <h2>Top 5 procesos por RAM</h2>
    <table>
        <tr><th>PID</th><th>Proceso</th><th>RAM</th><th>CPU</th></tr>
        $filas
    </table>
</div>

<footer>Generado con rayos-x · github.com/bgarciaa181/rayos-x</footer>
</div>
</body>
</html>
EOF

    echo "${VERDE}Informe HTML guardado en: $fichero${NORMAL}"
    echo "Ábrelo con el navegador, por ejemplo: xdg-open $fichero"
}

# ==========================================================
#  MODO EN VIVO
# ==========================================================

modo_vivo() {
    # Al pulsar Ctrl+C volvemos a mostrar el cursor y salimos
    trap 'tput cnorm; echo; echo "Saliendo del modo en vivo"; exit 0' INT
    tput civis

    while true; do
        # uso_cpu tarda 1 segundo, así que hace de "reloj" del bucle
        cpu=$(uso_cpu)
        ram=$(uso_ram)
        disco=$(uso_disco)

        clear
        echo "${CIAN}${NEGRITA} RAYOS-X · MODO EN VIVO${NORMAL}   $(hostname) · $(date '+%H:%M:%S')"
        echo
        printf " CPU    "; barra "$cpu"
        printf " RAM    "; barra "$ram"
        printf " Disco  "; barra "$disco"
        echo
        echo "${AZUL}${NEGRITA} Top 5 procesos por CPU${NORMAL}"
        ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -6 | sed 's/^/ /'
        echo
        echo " Pulsa Ctrl+C para salir"
    done
}

# ==========================================================
#  PROGRAMA PRINCIPAL
# ==========================================================

case "$1" in
    -h)
        ayuda
        ;;
    -g)
        recoger_datos
        fichero="informe_${NOMBRE}_$(date '+%Y%m%d_%H%M').txt"
        salida=$(informe)
        echo "$salida"
        # Guardamos el informe quitando los colores
        echo "$salida" | sed 's/\x1b\[[0-9;]*m//g' > "$fichero"
        echo "${VERDE}Informe guardado en: $fichero${NORMAL}"
        ;;
    -w)
        echo "Escaneando el equipo..."
        recoger_datos
        generar_html
        ;;
    -l)
        modo_vivo
        ;;
    "")
        recoger_datos
        informe
        ;;
    *)
        echo "Opción no válida: $1"
        ayuda
        exit 1
        ;;
esac