#!/bin/bash 
touch /var/log/veeam.log
echo `date` Starting failoverplan.service ... >> /var/log/veeam.log
pinging(){
ip="$2"
HOST_ip="$3"
vmname="$1"

while true
do
packet_lost1=$(ping -W 1 -c 5 "$ip" |grep -Eo '([0-9]{1,3}%)'|tr -d '%')

    if  [ "$packet_lost1" -ge 90 ]; then
            packet_lost2=$(ping -W 1 -c 5 ""$Vcenter""|grep -Eo '([0-9]{1,3}%)'|tr -d '%')
            if  [ "$packet_lost2" -le 10 ]; then
            packet_lost3=$(ping -W 1 -c 5 "$HOST_ip"|grep -Eo '([0-9]{1,3}%)'|tr -d '%')
            if  [ "$packet_lost3" -le 10 ]; then
            echo `date` "Powering Down $vmname" >> /var/log/veeam.log
            BlockoffVM $vmname &
            echo  `date`  Restoring $vmname FailOverPLan ... >>  /var/log/veeam.log
            echo 'Get-VBRFailoverPlan -Name '"$vmname-FOP"' | Start-VBRFailoverPlan' >> /home/script/VeeamFailoverPlan/N.ps1
            sed -i "/$vmname/d" /home/script/VeeamFailoverPlan/Inventory
            echo $vmname $ip $HOST_ip 0 0 >> /home/script/VeeamFailoverPlan/Inventory
            break
    else
            echo  `date`  Restoring $vmname FailOverPLan ... >>  /var/log/veeam.log
            echo 'Get-VBRFailoverPlan -Name '"$vmname-FOP"' | Start-VBRFailoverPlan' >> /home/script/VeeamFailoverPlan/N.ps1
            ### delet line by sed
            sed -i "/$vmname/d" /home/script/VeeamFailoverPlan/Inventory
            echo $vmname $ip $HOST_ip 0 1 >> /home/script/VeeamFailoverPlan/Inventory
            BlockNetworkInterface $vmname $HOST_ip &
            break

            fi
    else
            while true 
            do

                packet_lost2=$(ping -W 1 -c 5 "$VCENTERIP"|grep -Eo '([0-9]{1,3}%)'|tr -d '%')
            if  [ "$packet_lost2" -lt 10 ]; then
                    echo  `date`  Restoring $vmname FailOverPLan ... >>  /var/log/veeam.log
            echo 'Get-VBRFailoverPlan -Name '"$vmname-FOP"' | Start-VBRFailoverPlan' >> /home/script/VeeamFailoverPlan/N.ps1
            packet_lost3=$(ping -W 1 -c 3 "$HOST_ip"|grep -Eo '([0-9]{1,3}%)'|tr -d '%')
            if [ "$packet_lost3" -le 10 ]; then
                    echo `date` "Disconnecting Network & Powering Down $vmname" >> /var/log/veeam.log
            sed -i "/$vmname/d" /home/script/VeeamFailoverPlan/Inventory
            echo $vmname $ip $HOST_ip 0 0 >> /home/script/VeeamFailoverPlan/Inventory
            BlockoffVM $vmname &
            fi
            break
                  else
                          echo `date` "Vcenter not connect to restore $vmname FailOverPLan." >> /var/log/veeam.log
            fi
            done
            fi
    fi
    sleep 5
done
}

BlockoffVM(){
Vcenter=$VcenterIP
VMNAME=$1
VcenterPass="X7N8.pCrrDnXf5ws"
#$(openssl enc -aes-256-cbc -d -in PASSWORD -k "PASSWORD" 2>/dev/null)
API_KEY=$(curl -s -k -X POST https://"$Vcenter"/rest/com/vmware/cis/session -u '$VCENTERUSER':''$VcenterPass''|jq|grep value|awk '{print $2}'|tr -d '\"')
VMID=$(curl -s -X GET --header 'Accept: application/json' --header 'vmware-api-session-id: '$API_KEY''  'https://'$Vcenter'/rest/vcenter/vm?filter.power_states=POWERED_ON' --insecure |jq|grep -B1 "\"$VMNAME\"," | grep '"vm"'|awk '{print $2}'|tr -d ',' |tr -d '\"')
curl -s -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --header 'vmware-api-session-id: '$API_KEY'' 'https://'$Vcenter'/rest/vcenter/vm/'$VMID'/guest/power?action=shutdown' --insecure|jq > /dev/null
if [ $? -eq 0 ];
then
        echo `date`  VM $VMNAME Powerd off because of problem! >> /var/log/veeam.log
else
        echo `date`  Can not Poweroff vm because VM is not exist or not powered on yet! >> /var/log/veeam.log
fi
}

BlockNetworkInterface(){
Vcenter="$Vcenter"
HOST_ip="$2"
vmname="$1"
VcenterPass=""
while true
do
        PacketLostHost=$(ping -W 1 -c 5 "$HOST_ip" |grep -Eo '([0-9]{1,3}%)'|tr -d '%')
         if  [ "$PacketLostHost" -le 10 ]; then
        ###Disconnect VM's Network NIC's
        sleep 1
        API_KEY=$(curl -s -k -X POST https://"$Vcenter"/rest/com/vmware/cis/session -u '$VCENTERUSER':''$VcenterPass''|jq|grep value|awk '{print $2}'|tr -d '\"')
        VMID=$(curl -s -X GET --header 'Accept: application/json' --header 'vmware-api-session-id: '$API_KEY''  'https://'$Vcenter'/rest/vcenter/vm?filter.power_states=POWERED_ON' --insecure |jq|grep -B1 "\"$vmname\"," | grep '"vm"'|awk '{print $2}'|tr -d ',' |tr -d '\"')
        NIC_LIST=$(curl -s -X  GET --header 'Accept: application/json' --header 'vmware-api-session-id: '$API_KEY'' 'https://'"$Vcenter"'/rest/vcenter/vm/'$VMID'/hardware/ethernet' --insecure|jq|grep nic|awk '{print $2}'|tr -d '\"')
        for interface in $NIC_LIST
        do
                sleep 1
        curl -s -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --header 'vmware-api-session-id: '$API_KEY'' 'https://'"$Vcenter"'/rest/vcenter/vm/'"$VMID"'/hardware/ethernet/'"$interface"'/disconnect' --insecure
        done
        break
         fi
sleep 1
done
 }

main(){
rm -f /home/script/VeeamFailoverPlan/N.ps1
cat /home/script/VeeamFailoverPlan/Inventory|while read line
do
        line_counter=$((line_counter + 1))
        check_vm=$(echo $line|cut -d ' ' -f4|grep -Eo '\b(0|[0-1]\d*)\b')
        if [ "$?" -eq 0 ]
        then
                check_host=$(echo $line|cut -d ' ' -f5|grep -Eo '\b(0|[0-1]\d*)\b')
                if [ "$?" -eq 0 ]
                then
                        if [[ "$check_vm" -eq 1 && "$check_host" -eq 0 ]]
                        then
                                pinging $line &
                                sleep 1
                           elif [[ "$check_vm" -eq 0  &&  "$check_host" -eq 1 ]]
                           then
                                   HOST_ip=$(echo $line|awk '{print $3}')
                                   vmname=$(echo $line|awk '{print $1}')
                                BlockNetworkInterface $vmname $HOST_ip &
                                sleep 1
                        fi

                else
                echo "The variable check_host in line $line_counter that is 1 or 0 was not set in inventory." >> /var/log/veeam.log
                exit 1
                fi
        else

                echo "The variable check_vm in line $line_counter that is 1 or 0 was not set in inventory." >> /var/log/veeam.log
                exit 1
        fi
done

VeeamServer_ip=$VeeamServer_IP
###Check Vcenter Availability & Execute FailoverPlan.
while true
do
sleep 5
packet_lost_VeeamServer=$(ping -W 1 -c 5 "$VeeamServer_ip" |grep -Eo '([0-9]{1,3}%)'|tr -d '%')
if  [ "$packet_lost_VeeamServer" -ge 90 ]; then
   echo  `date` VeeamServer: $VeeamServer_ip is Unreachable Service failoverplan.service Restarting ... >> /var/log/veeam.log
        systemctl restart failoverplan.service
fi
if [[ -f /home/script/VeeamFailoverPlan/N.ps1 && -s /home/script/VeeamFailoverPlan/N.ps1 ]];
then
ansible-playbook -i /etc/ansible/hosts /home/script/VeeamFailoverPlan/ansible.yml >> /var/log/veeam.log
cat /home/script/VeeamFailoverPlan/N.ps1|while read FailoverCommand
do
        sed -i "/$FailoverCommand/d" /home/script/VeeamFailoverPlan/N.ps1
done

fi
done &
}

main

