#!/bin/bash 

# Programa que evita que la temperatura del CPU alcance un máximo prestablecido, interrumpiendo de manera temporal los procesos del CPU.
# Los primeros programas en interrumpirse son los que más consumen el CPU.

declare -a pid
declare -a parent

LOGFILE="logkillvoraxcpu.log"
MYPID=$$

TEMPMAX=80	# Temperatura maxima
TEMPEST=75	# Temperatura de estabilizacion
PAUSE_I="1s"	# Pausa luego de interrumpir un proceso

writeoutput() {
	echo "[$(date +%s)]: $@"
	echo "[$(date +%s)]: $@" >> $LOGFILE

}

getParents() {
	local pid="$PPID"
	local parents=$(pstree -A -n -T   -s -p  -l  $PPID | head -n1)
	local garbage=${parents#*$pid}
	local offset=$(( ${#parents} - ${#garbage} ))
	local pid=()

	parents=$(echo ${parents:0:$offset}) # quita los descendientes del padre de $$
	parents=$(echo $parents | sed -e 's/---/   /g')

	local i=0
	for name in $parents 
	do
		pid[$i]=$(echo $name | cut -f 2 -d '(' | cut -f 1 -d ')')
		i=$(($i+1))
	done
	echo "${pid[@]}"

}

isInArray() {

	declare -n array="$1"
	local value="$2"
	len=${#array[@]}

	for((i=0; i < $len; i++))
	do
		if [ "$value" = "${array[$i]}" ]
		then
			return 1
		fi
	done
	return 0
}


isParent() {
	isInArray parent  "$1"
	return $?
}

# Indica si el PID existe retorna 1 si existe y 0 si no
existPID() {
	isInArray pid  "$1"
	return $?
}


getTemp() {
	
	TEMP=$(sensors | grep CPU | awk '{print $2}'); TEMP=${TEMP:1:2}

	# A veces la consulta a sensors puede arrojar basura, no conozco la razon. Nos aseguramos que no retorne basura
	[ $TEMP -lt 70 -o $TEMP -ge 70 ] 2>/dev/null
	while [ $? -ne 0 ]
	do 
		writeoutput "Basura en la consulta a sensors" 
		TEMP=$(sensors | grep CPU | awk '{print $2}'); TEMP=${TEMP:1:2}
		[ $TEMP -lt 70 -o $TEMP -ge 70 ] 2>/dev/null
	done
	
	echo $TEMP
}

getState() {
	echo $(ps  --pid $1 -o state | tail -n1)

}

isElegible() {
	local PID=$1

	existPID $PID
	[ $? -eq 1 ] && return 0	
	isParent $PID 
	[ $? -eq 1 ] && return 0
	[ $MYPID -eq $PID ] && return 0

	return 1
}


parent=( $(echo $(getParents)) ) 

while true
do
	TEMP=$(getTemp)


	if [ $TEMP -ge $TEMPMAX ]
	then 
		writeoutput "Temperatura del CPU excedida: ${TEMP}°C"
		writeoutput "$(top -bn1 | head -n3 | tail -n1)"
		ALL=$(ps -A -o comm:20,pid,ppid,pcpu,state | sort  -n -k 4 )

		while true
		do
			PI=$(echo "$ALL" | tail -n1 )
			#writeoutput "PI $PI"
			NAME=$(echo $PI | dd count=20 bs=1 2>/dev/null)
			PID=$(echo $PI | awk '{print $2}')
			MPPID=$(echo $PI | awk '{print $3}')
			STATE=$(echo $PI | awk '{print $5}')

					
			#existPID $PID || writeoutput "$? El pid: $PID esta registrado"
			#isParent $PID && writeoutput "$? El pid: $PID no es padre"
			
			#existPID $PID 
			#isParent $PID
			#echo "Resultado de la operacion $?"

			writeoutput  "${#pid[@]} Procesos detenidos. PIDs:  ${pid[@]}" 
			
			isElegible $PID
			if [ $? -eq 1 ]
			then 
				writeoutput "Intentando detener $NAME, pid: $PID"
				kill -STOP $PID
				if [ $? -ne 0 ]
				then 
					writeoutput "Error al intentar detener el proceso $NAME, $PID"
					# Lo intentara con el siguiente proceso
					LINES=$(echo "$ALL" | wc -l)
					ALL=$(echo "$ALL" | head -n $(($LINES-1)) )
					continue
					# exit 1
				fi

				
				pid[${#pid[@]}]=$PID
				writeoutput  "Se detuvo el proceso: $NAME pid: $PID"

				# Innecesario:
				#sleep 0.1s # Una pequena pausa para que al proceso le de tiempo de atender la senal de STOP (es suficiente?)
				#if [ "$(getState $PID)" != 'T' ]
				#then 
				#	echo "El proceso $NAME, con pid: $PID, no es detenible, se reintentara con el siguiente proceso que mas consume CPU"
				#	LINES=$(echo "$ALL" | wc -l)
				#	ALL=$(echo "$ALL" | head -n $(($LINES-1)) )
				#	continue
				#else 
				#	break
				#fi
			else 
				# El proceso $PID esta detenido o este mismo proceso ($$), se reintenta con el siguiente
				LINES=$(echo "$ALL" | wc -l)
				ALL=$(echo "$ALL" | head -n $(($LINES-1)) )
				continue
			fi
			break

		done
		writeoutput "Temperatura excedida por $NAME, pid: $PID con padre $MPPID, detenido hasta reducir la temperatura a menos de ${TEMPEST}°C"

		writeoutput "Pausa de $PAUSE_I"
		sleep 1s
		writeoutput "Temperatura del CPU: ${TEMP}°C"
		writeoutput "$(top -bn1 | head -n3 | tail -n1)"
		
	elif [ $TEMP -lt $TEMPEST ]
	then 
		if [ ${#pid[@]} -ne 0 ]
		then 
			# Pone en marcha todos los procesos detenidos
			while [	${#pid[@]} -ne 0 ]
			do
				writeoutput "Continuando el proceso con PID ${pid[0]}"
				kill -CONT ${pid[0]} || writeoutput  "Error intentando interrumpir el proceso con pid: ${pid[0]}"
				sleep 0.4s				
				pid=( "${pid[@]:1:$((${#pid[@]} -1))}"  ) 

				writeoutput "PIDs todavia detenidos ${#pid[@]}: ${pid[@]}"
			done

		fi
	

	fi
	sleep 0.2s
done
