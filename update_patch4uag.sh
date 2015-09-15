#!/bin/bash
########################################################################
# Copyright (C) 2015
#  
# 
#ALL RIGHTS RESERVED
#
#
# Authors: Guoyong
#
########################################################################
function is_tgzFile
{
  tgzfile=$1
  if [ ${tgzfile##*.} != "tgz" ]
  then
    #echo "not tgz file"
    return 0
  else
#    echo "is tgz file"
    return 1
  fi
}

function compareMD5
{
#1: old file; 2: new file
 oldFileMD5=`md5sum $1 | awk '{print $1}'`
 newFileMD5=`md5sum $2 | awk '{print $1}'`
 #echo $oldFileMD5
 #echo $newFileMD5
 if [ "$oldFileMD5" == "$newFileMD5" ]
 then 
    return 1 
 else 
    return 0
 fi
}

function getIMSServiceStatus
{
  result=`readShm | grep Shelf -A1 | grep -v Shelf | awk '{print $7}'`
  case $result in
    STATE_OOS)
       return 0
       ;;
    STATE_MAINTENANCE)
       return 1
       ;;
    STATE_INS_ACTIVE)
       return 2
       ;;
    *)
       return 3
       ;;
  esac
}

function waitBeActive
{
  waiting_seconds=120
  echo -n "waiting IMS service to be active"
  while(( "$waiting_seconds" > 0 ))
  do
     getIMSServiceStatus
     if [ $? -eq 2 ]
     then
       echo -e "\n"
       #echo "Active! Everything is OK now"
       return 1
     else
       echo -n "."
       sleep 1
       let "waiting_seconds--"
     fi
  done
  echo -e "\n"
  return 0
}
function handlePatch
{
# para 1 is the path
# result 0: updated successfully, 1: no need to update
  path="/usr/IMS/current/bin/"
  if [ $# != 0 ]
  then 
	 path=$1
  fi
  compareMD5 $path$patch $patch 
  if [ $? -eq 0 ] 
  then
        #echo "start to update patch: $patch"
        if [[ $backupDir != "" ]]; then
          echo "backup patch: $patch firstly"
          \cp $path$patch $backupDir/$patch-$date_time-bak
          echo -e "patch: \e[1;35m $patch \e[0m is backed up \e[1;32msuccessfully! \e[0m" 
        fi
        \cp $patch $path$patch  
        compareMD5 $path$patch $patch 
        if [ $? -eq 1 ] 
        then
          echo -e "patch: \e[1;35m $patch \e[0m is updated \e[1;32msuccessfully! \e[0m"
          echo -e "the path is: \e[1;32m $path \e[0m"
          echo ""
          let "num_updated_patch++"
          return 0
        else
          echo -e "\e[1;31m something bad happened, failed to update $patch, exit! \e[0m"
          exit
        fi
  else
        echo -e "\e[1;33mthe md5 info of the patch: $patch is the same with old file, no need to update! \n\e[0m"
        let "num_noneed_updated_patch++"
        return 1
  fi
}

function outputResult
{
  echo -e "\e[1;32m output result: \e[0m"
  echo -e "          the number of all patches:                      \e[1;32m $num_all_patch \e[0m"
  echo -e "          the number of patches updated successfully:     \e[1;32m $num_updated_patch \e[0m"
  echo -e "          the number of patches no need to update:        \e[1;35m $num_noneed_updated_patch \e[0m"
  echo -e "          the number of patches need to update mannually: \e[1;31m $num_mannual_patch \e[0m"
  if [ $num_mannual_patch -ne 0 ]; then
    echo -e "    this unknown patches list is: \e[1;31m$mannual_patch_list\e[0m"
  fi

}

function usage
{
  showVersion
  echo -e "\e[1;33m usage:\e[0m\e[1;32m $0 official_patch.tgz_file\e[0m  or \e[1;32m$0 official_patch.tgz_file Backup_path\n \e[0m"
 
}

function showVersion
{
  echo -e "\n"
  echo -e "\e[0;31;1m                       ++++++                 update_patch4uag.sh script version 2.4          ++++++ \e[0m"
  echo -e "\e[0;31;1m                       ++++++                       For Personal Use ONLY!!                   ++++++ \e[0m"
  echo -e "\e[0;31;1m                       ++++++  Any issue, please contact guoyong.zhang@mitel.com for support  ++++++\n \e[0m"
}

if [[ $# -ne 1 && $# -ne 2 ]]; then
  #statements
  usage
  echo "exit...."
  exit
fi
#echo -e "\e[1;32m ############ start ########### \e[0m"
usage
tarPatchFile=$1
backupDir=""
is_tgzFile $tarPatchFile
if [ $? -eq 0 ]
then
 echo -e "\e[0;31;1m it's not right tar patch file! exit..... \e[0m"
 exit
fi

date_time=`date +"%Y-%m-%d-%H-%M"` 

if [[ $# -eq 2 ]]; then
  #statements
  backupDir=$2
  if [[ ! -d $backupDir ]]; then
    echo -e "\e[1;33m the bakup dir doesn't exist,  will create it firstly for you!\e[0m"
    mkdir -p $backupDir
  fi
fi

DATE=`date +"%m-%d-%H-%M-%S"`
PATCHBAKDIR="/data/storage/"
echo "unzip patch...."
tar zxvf $tarPatchFile >/dev/null 2>&1
if [ $? -ne 0 ]
then
 echo -e "\e[1;31munzip tar patch failure! exit! \e[0m"
 exit
else
 echo -e "\e[1;32munzip tar patch successfully! \e[0m"
fi

echo "stopping IMS service, pls wait..................."
service IMS stop 
echo ""
getIMSServiceStatus
if [ $? -ne 3 ]
then
  echo "failed to stop IMS service, exit!"
exit
fi


num_all_patch=0
num_updated_patch=0
num_noneed_updated_patch=0
num_mannual_patch=0

b_schemaUpdated=0
mannual_patch_list=""

tmp=`tar tf $tarPatchFile 2>/dev/null`
while read tarSinglePatch
do
    is_tgzFile $tarSinglePatch
    if [ $? -eq 0 ]
	then
       if [[ "$tarSinglePatch" =~  .*db_upgrade.* ]]
       then
          echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
          echo "Note: there is a db upgrading script in the patch! It's $tarSinglePatch"
          echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
          echo " "
          continue
       fi
    
       if [ "$tarSinglePatch" != "software.info" -a "$tarSinglePatch" != "md5sum.info" -a "$tarSinglePatch" != "diff.txt" ]
       then
	   	  echo -e "\e[1;31m $tarSinglePatch is not right patch file! exit! \e[0m"
          exit
       fi
       
       if [ "$tarSinglePatch" == "diff.txt" ]
       then
          echo -e "!!!!!!!!watch out!!!!!! there should not be such diff.txt file in the patch, there must be something wrong, just ignore this time to make the upgrading continue, make sure to check with SCM for this\n "
          continue
       fi
       continue
	fi

	echo -e "going to handle tar patch: \e[1;32m$tarSinglePatch .... \e[0m" 
    
    tmpa=`tar zxvf $tarSinglePatch`
    tmpa_array=($tmpa)
    patch=${tmpa_array[0]}
    if [ $patch == "md5sum.info" ]
    then
        patch=${tmpa_array[1]}
    fi
    echo -e "the patch name is:\e[1;32m$patch\e[0m"
    if [ -d "$patch" ]
    then
       echo -e "\e[1;31m Waring: the patch :$patch is a folder! exit! \e[0m"
       exit
    fi
    if [ "`md5sum $patch`" != "`cat md5sum.info`" ]
    then
       echo -e "\e[1;31m the md5 of $patch is inconsistent with md5sum.info! exit! \e[0m"
       exit
    #else
     #  echo -e "the md5 of $patch is \e[1;32mcorrect! \e[0m"
     #  echo  "it is: `md5sum $patch`"
    fi
    let "num_all_patch++"
    case $patch in
    *.cfg)
       handlePatch /usr/IMS/current/schema/
       if [ $? -eq 0 ]
       then       
       b_schemaUpdated=1
       fi
       ;;
    conf_Service.sh)
       handlePatch /usr/IMS/exports/scripts/
       ;;
    appsrvInstall.sh|GF_Monitor.sh)
       handlePatch /usr/IMS/current/provisioning/scripts/
       ;;
    fp*|cmgrd)
       handlePatch /usr/local/6bin/
       if [ $? -eq 0 ]
       then
          echo -e "\e[1;35mNote: it is fp patch, will replace base path patch as well\n \e[0m"
          \cp $patch /usr/IMS/exports/images/AM_sw/fpath/usr/local/6bin/$patch
       fi
       ;;
    mcore.sh|stop_dp.sh|start_fpm.sh|start_dp_system.sh|start_dp_mgm.sh|mcore_start_1cp1fp.sh)
       handlePatch /usr/local/6WINDGate/etc/scripts/
       if [ $? -eq 0 ]
       then
          echo -e "\e[1;35mNote: it is fp related patch, will replace base path patch as well\n \e[0m"
          \cp $patch /usr/IMS/exports/images/AM_sw/fpath/usr/local/6WINDGate/etc/scripts/$patch
       fi
       ;;
    libfpn-shmem.so|libfp_shm.so|lib6whas.so)
       handlePatch /usr/local/lib64/
       if [ $? -eq 0 ]
       then
          echo -e "\e[1;35mNote: it is fp patch, will replace base path patch as well\n \e[0m"
          \cp $patch /usr/IMS/exports/images/AM_sw/fpath/usr/local/lib64/$patch
       fi
       ;;
    *Mgr|*server|bladeMon|mod_mxa.so|ecscf|lrf|dnsResolver|utimacoLi*|pm|dm|mlog*|cdrLogger|snmpd|perfMon*|pm_*.sh|lighttpd|controlDb.sh|controlDb.sh|SM|mon_getFanStatus.sh|mon_getPowerSupplyStatus.sh|customReboot.sh|alarmGenerator|cleanupLogFiles.sh|mysql_reset_user_passwords.sh|mavcrypt|ovldMon)
       handlePatch /usr/IMS/current/bin/
       ;;
    *sql)
       handlePatch /usr/IMS/current/sql/
       if [ $? -eq 0 ]
       then
       b_schemaUpdated=1
       fi
       ;;
    *hdr)
       handlePatch /usr/IMS/current/tmm_def/
       ;;
    ems.ear|cps.ear)
       handlePatch /usr/IMS/current/provisioning/dist/
       ;;
    Folder*.xml|ClassDefination.xml)
       handlePatch /usr/IMS/current/provisioning/glassfish/lib/mavenir/xml/uag/v40-platform/
       ;;
    *.xsd)
       handlePatch /usr/IMS/current/provisioning/glassfish/lib/mavenir/schema/
       ;;
    sys*.sh|rem*.sh|exp*.sh|common.tcl|common.sh|cleanup_backupfile.sh|backupmTasDB.sh|SERestore.sh|SEFileset.dat|SEBackup.sh|CONFIGFileset.dat|AMFileset.dat)
       handlePatch /usr/IMS/current/script/backup/
       ;;
    install_fpath.sh)
       handlePatch /usr/IMS/current/fpath/
       ;;
    web_agent.properties)                                                                                                                                                                                                             
       handlePatch /usr/IMS/current/provisioning/glassfish/lib/mavenir/
       ;; 
    datasource.xml)
       handlePatch /usr/IMS/current/provisioning/config/
       ;;   
    *)
       echo -e "\e[1;31m unknown patch file, pls update patch mannually: $patch!!\e[0m"
       let "num_mannual_patch++"
       mannual_patch_list=$mannual_patch_list" $patch"
       ;;
    esac
done <<EOF
$tmp
EOF

if [ $b_schemaUpdated -eq 1 ]
then
  echo -e "\e[1;31m        NOTIFY: won't start IMS service due to sql/cfg file updated \e[0m"
fi

if [ $num_mannual_patch -ne 0 ]
then
  echo -e "\e[1;31m        NOTIFY: won't start IMS service due to some unknown patches \e[0m"
fi

outputResult

if [ $b_schemaUpdated -eq 0 -a $num_mannual_patch -eq 0 ]
then
  echo "starting IMS service, pls wait...."
  service IMS start
  waitBeActive
  if [ $? -ne 1 ]
  then
    echo -e "\n\e[1;31m        ########## Alert: Bad luck! The status of load can't be active!      ######## \n\e[0m"
  else
    echo -e "\n\e[1;32m        #########   Congratuations! IMS service is active, all done! Enjoy!   ####### \n\e[0m"
  fi
fi
# The End


