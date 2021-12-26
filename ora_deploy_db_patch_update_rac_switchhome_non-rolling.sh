#######################################################################################################
# ora_deploy_db_patch_update_rac_switchhome_non-rolling.sh
#
# Description: Run qtr deploy patch process for each database in data list
#              for a node switching database home from curent home to a patched home
#              and running the datapatch
#
# Dependancies:  Process Assumes Oracle non-RAC
#
#                ora_deploy_db_datapatch_non-rolling.sh <paramters will be created as part of process>
#                    Script must be located in the same directory with this script ora_deploy_db_patch_update_nonrac.sh
#
#                ora_deploy_db_patch_nodes_switchhome_{env}.txt (${inputfile}) can pass as parameter a file with a different node list
#                                       node dbinstance OLD_ORACLE_HOME NEW_ORACLE_HOME racdbname
#                                       node dbinstance OLD_ORACLE_HOME NEW_ORACLE_HOME racdbname
#
#                ora_deploy_pre_patch_exec_{env}.txt     ** optional if files do not exist process will ignore
# 					  list of scripts with full path to execute prior to patching
#
#                ora_deploy_post_patch_exec_{env}.txt    ** optional if files do not exist process will ignore
# 					  list of scripts with full path to execute after patching
#        
#               All Instances for node must exist in the /etc/oratab for process to get ORACLE_HOME
#               The cluster dbname is the database name as identified in clusterware for RAC, if not present then assumes non-RAC
#               The Cluster dbname is important as it tends to be different between primary and standby clusters for database
#               as name in cluster tends to be same as DB unique name.
#
# Parameters:    environment set to use for paramter files for example
#                pass value of dev and all file parameters become filename_${env}.txt
#                if no value passed then filename is filename.txt
#
# Output:  <Script location on file system>/logs/ora_deploy_db_patch_switchhome_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_db_patch_switchome.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_db_patch_switchhome.sh <env>
#######################################################################################################
#
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_db_patch_nodes_switchhome.txt
# if environment provided then it is ora_deploy_db_patch_nodes_switchhome_${envinputfile}.txt
####################################################################################
export envinputfile=$1

#####################################################
# Script environment
#####################################################
# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=ora_deploy_db_patch_switchhome_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=ms_us@advizex.com
export EMAIL_LIST=ms_us@advizex.com

echo "###########################################################################################"
echo "###########################################################################################" >> ${LOG}
echo "Checking Parameters and files for Patch/Switch home Update Process....."
echo "Checking Parameters and files for Patch/switch home Update Process....." >> ${LOG}

################################################################################################
# Configuration Files for datapatch apply for instances this is standard and not configurable
# is is a fixed list of nodes, instance and dbname to do the post datapatch operation
# the other files for pathfile and patupupdate file are also considered fix, but
# setting the environment variables to other file names will allow those files to be used
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_patch_nodes_switchhome.txt
   export dbpatchupdatepreexec=ora_deploy_pre_patch_exec.txt
   export dbpatchupdatepostexec=ora_deploy_post_patch_exec.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_patch_nodes_switchhome_${envinputfile}.txt
   export dbpatchupdatepreexec=ora_deploy_pre_patch_exec_${envinputfile}.txt
   export dbpatchupdatepostexec=ora_deploy_post_patch_exec_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process patch/switch home update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process patch/switch home update." >> ${LOG}
   exit 8
fi

echo "#################################################################################################"
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "${inputfile}"
echo "${inputfile}" >> ${LOG}
echo "${dbpatchupdatepreexec}"
echo "${dbpatchupdatepreexec}" >> ${LOG}
echo "${dbpatchupdatepostexec}"
echo "${dbpatchupdatepostexec}" >> ${LOG}

# Set Local hostname
export HOSTNAME=`hostname`
echo ${HOSTNAME}
echo ${HOSTNAME} >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running DB Patch/Switch Home for each node/home in ${inputfile}"
echo "Running DB Patch/Switch Home for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

#################################################################
# Run any scripts put in the pre patch execution file
if [ -f "${SCRIPTLOC}/${dbpatchupdatepreexec}" ] 
 then
echo "Running Pre Patch Processes as defined in ${dbpatchupdatepostexec}"
echo "Running Pre Patch Processes as defined in ${dbpatchupdatepostexec}" >> ${LOG}
while read -r line_script
do
    ssh -n ${nodename} ${line_script}
done < "${SCRIPTLOC}/${dbpatchupdatepreexec}"
fi

# go through each node in the list in the file and execute upgrade/patching
while read -r line
do 
   ########################################################
   # Assign the nodename and home(s) for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export instname=`echo ${line}| awk '{print $2}'`
   export oldoraclehome=`echo ${line}| awk '{print $3}'`
   export neworaclehome=`echo ${line}| awk '{print $4}'`
   export racdbname=`echo ${line}| awk '{print $5}'`
   
   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing Database ${instname} from ${oldoraclehome} to ${neworaclehome} for ${nodename}"
   echo "Processing Database ${instname} from ${oldoraclehome} to ${neworaclehome} for ${nodename}" >> ${LOG}
   
   ###############################################################################################
   # Check if database is running in Old ORACLE_HOME we are patching   
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   # check database instance running on node being patched/switch home
   echo "Checking if Status for ${instname} on ${nodename} in ${oldoraclehome}"
   echo "Checking if Status for ${instname} on ${nodename} in ${oldoraclehome}" >> ${LOG}

   # Check ORACLE_HOME for instance is our oracle home that we are patching
   cmd="echo `/usr/local/bin/dbhome ${instname}` | grep ${oldoraclehome}"
   export result=`ssh -n ${nodename} ${cmd}`

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "Check for running instance for ${instname} on ${nodename} in ${oldoraclehome} Failed, aborting......"
      echo "Check for running instance for ${instname} on ${nodename} in ${oldoraclehome} Failed, aborting......" >> ${LOG}
      exit 8
   fi
  
   ###############################################################################################
   # Check if standby database
   ###############################################################################################
   echo "Checking if ${instname} is a Standby Database"
   echo "Checking if ${instname} is a Standby Database" >> ${LOG}
   export cmd="export ORACLE_HOME=${oldoraclehome}; export ORACLE_SID=${instname}; echo -e 'set pagesize 0 \nselect database_role from v\$database;' | ${oldoraclehome}/bin/sqlplus -s '/ as sysdba'"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   export dbmode=$(ssh -n ${nodename} ${cmd})
  
   echo "Database Mode is -> ${dbmode}" 
   echo "Database Mode is -> ${dbmode}" >> ${LOG}
   
   ###############################################################################################
   # Switch ORACLE_HOME, update /etc/oratab
   ###############################################################################################
   # create a temp /etc/oratab file on remote node
   echo "Updating /etc/oratab for ${instname} from ${oldoraclehome} to ${neworaclehome}" 
   echo "Updating /etc/oratab for ${instname} from ${oldoraclehome} to ${neworaclehome}" >> ${LOG}
   srch="${instname}:${oldoraclehome}"
   repl="${instname}:${neworaclehome}"
   cmd="sed 's|${srch}|${repl}|g' /etc/oratab > ${HOME}/oratab.new"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "/etc/oratab temp new for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "/etc/oratab temp new for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   # take backup of existing /etc/oratab
   cmd="cp /etc/oratab $HOME/oratab.save"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "/etc/oratab Backup for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "/etc/oratab Backup for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   # Put the new oratab.new in place of /etc/oratab
   cmd="cp ${HOME}/oratab.new /etc/oratab"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "/etc/oratab Replace for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "/etc/oratab Replace for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   # Remove the /etc/oratab   
   cmd="rm -f ${HOME}/oratab.new"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "Removed of temp new /etc/oratab for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "Removed of temp new /etc/oratab for ${instname} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   ###############################################################################################
   # Shutdown instance 
   ###############################################################################################
   echo "Shutting Down ${instname} in ${oldoraclehome}" 
   echo "Shutting Down ${instname} in ${oldoraclehome}" >> ${LOG}
   
   if [ -z ${racdbname} ]
	then
      echo "Shutting down non-RAC instance ${instname} on ${nodename}"
	  echo "Shutting down non-RAC instance ${instname} on ${nodename}" >> ${LOG}
	  export cmd="export ORACLE_HOME=${oldoraclehome}; export ORACLE_SID=${instname}; echo 'shutdown immediate' | ${ORACLE_HOME}/bin/sqlplus '/ as sysdba'"
	  ssh -n ${nodename} ${cmd} >> ${LOG}
		 
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${instname} on ${nodename} is shutdown, continuing"
         echo "Oracle instance ${instname} on ${nodename} is sutdown, continuing" >> ${LOG}
      else
         echo "Oracle instance ${instname} on ${nodename} did not shutdown, aborting process"
         echo "Oracle instance ${instname} on ${nodename} did not shutdown, aborting process" >> ${LOG}
         exit 8
	  fi
   else 
      echo "Shutting down RAC database for ${instname} on ${nodename} for ${racdbname}"
	  echo "Shutting down RAC database for ${instname} on ${nodename} for ${racdbname}" >> ${LOG}
      export cmd="export ORACLE_HOME=${oldoraclehome}; export ORACLE_SID=${instname}; ${oldoraclehome}/bin/srvctl stop database -d ${racdbname}" 
	  ssh -n ${nodename} ${cmd} >> ${LOG}
		 
	  # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${instname} on ${nodename} for ${racdbname} is shutdown, continuing"
         echo "Oracle instance ${instname} on ${nodename} for ${racdbname} is shutdown, continuing" >> ${LOG}
      else
         echo "Oracle instance ${instname} on ${nodename} for ${racdbname} did not shutdown, aborting process"
         echo "Oracle instance ${instname} on ${nodename} for ${racdbname} did not shutdown, aborting process" >> ${LOG}
         exit 8
	  fi
   fi
 
   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   ###############################################################################################
   # Copy files from dbs location for database from old home to new home
   ###############################################################################################
   echo "Copy all files from ${oldoraclehome}/dbs to ${neworaclehome}/dbs for ${instname} on ${nodename}"
   echo "Copy all files from ${oldoraclehome}/dbs to ${neworaclehome}/dbs for ${instname} on ${nodename}" >> ${LOG}
   cmd="cp ${oldoraclehome}/dbs/*${instname}* ${neworaclehome}/dbs"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   ###############################################################################################
   # If Primary database run datapatch
   ###############################################################################################
   if [ "${dbmode}" = "PRIMARY" ]; then
      #################################################################################################
      # Startup database instances on Node for ORACLE_HOME being patched in upgrade mode for datapatch
      # Assumes /etc/oratab is up to date and has instance names in there
      #################################################################################################
      echo "Starting instance ${instname} on ${nodename} in New ORACLE_HOME Upgrade Mode -> ${neworaclehome}."
      echo "Starting instance ${instname} on ${nodename} in New ORACLE_HOME Upgrade Mode -> ${neworaclehome}." >> ${LOG}

      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; echo -e 'startup mount;' | ${neworaclehome}/bin/sqlplus '/ as sysdba'"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database instance ${instname} on ${nodename} Started"
         echo "Oracle database instance ${instname} on ${nodename} Started" >> ${LOG}
      else
         echo "Oracle database instance ${instname} on ${nodename} Start Failed, aborting....."
         echo "Oracle database instance ${instname} on ${nodename} Start Failed, aborting....." >> ${LOG}
         exit 8
      fi

      # Put in if there is an encryption wallet that is not auto open
      #echo "--" >> ${LOG}
      #echo "Open Wallet for ${instname} on ${nodename}"
      #echo "Open Wallet for ${instname} on ${nodename}" >> ${LOG}
      #export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; echo 'alter system set encryption wallet open identified by \"<password>\" ;' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
      #ssh -n ${nodename} ${cmd} >> ${LOG}

      # open database in upgrade mode
      echo "--" >> ${LOG}
      echo "Open Database Upgrade for ${instname} on ${nodename}"
      echo "Open Database Upgrade for ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; echo 'alter database open upgrade ;' | ${neworaclehome}/bin/sqlplus '/ AS SYSDBA'"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}
   
      # Check execution of Open Upgrade
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${instname} on ${nodename} is in upgrade state, continuing"
         echo "Oracle instance ${instname} on ${nodename} is in upgrade state, continuing" >> ${LOG}
      else
         echo "Oracle instance ${instname} on ${nodename} is not in upgrade state, aborting process"
         echo "Oracle instance ${instname} on ${nodename} is not in upgrade state, aborting process" >> ${LOG}
         exit 8
      fi
   
      # Execute the datapatch
      echo "Running datapatch for ${instname} on ${nodename}"
      echo "Running datapatch for ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; ${neworaclehome}/OPatch/datapatch -verbose"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}
   
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "datapatch on ${nodename} for instance ${instname} was successful." 
         echo "datapatch on ${nodename} for instance ${instname} was successful."  >> ${LOG}
      else
         echo "datapatch on ${nodename} for instance ${instname} was not successful." 
         echo "datapatch on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
         exit 8
      fi 
   
      # Shutdown instance so we can open it back up normal post datapatch
      echo "--" >> ${LOG}
      echo "DataPatch Completed, Shutdown for ${instname} on ${nodename}"
      echo "DataPatch Completed, Shutdown for ${instname} on ${nodename}" >> ${LOG}   
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; echo 'shutdown immediate' | ${neworaclehome}/bin/sqlplus '/ AS SYSDBA'"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check shutdown ok datapatch
      if [ $? -eq 0 ]; then
         echo "Shutdown for ${instname} on ${nodename} ok, continuing"
         echo "Shutdown for ${instname} on ${nodename} ok, continuing" >> ${LOG}
      else
         echo "Shutdown for ${instname} on ${nodename} not ok, aborting process"
         echo "Shutdown for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
         exit 8
      fi

      if [ -z ${racdbname} ]
	   then
	     # Handle non-RAC
         echo "Starting normal non-RAC instance ${instname} on ${nodename} in new ORACLE_HOME -> ${neworaclehome}"
         echo "Starting normal non-RAC instance ${instname} on ${nodename} in new ORACLE_HOME -> ${neworaclehome}" >> ${LOG}
         export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; echo 'startup' | ${neworaclehome}/bin/sqlplus '/ as sysdba'" 
         echo "Running...... ${cmd}"
         echo "Running...... ${cmd}" >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}

         # Check execution of instance/db state was successful
         if [ $? -eq 0 ]; then
            echo "Oracle instance ${instname} on ${nodename} is started, continuing"
            echo "Oracle instance ${instname} on ${nodename} is started, continuing" >> ${LOG}
         else
            echo "Oracle instance ${instname} on ${nodename} did not start, aborting process"
            echo "Oracle instance ${instname} on ${nodename} did not start, aborting process" >> ${LOG}
            exit 8
         fi 
      else
         # Handle rac
      fi
	  
   else
      if [ -z ${racdbname} ]
	   then
	     # Handle Non-rac
         echo "Starting normal non-RAC Standby Instance ${instname} on ${nodename} to Mount State in new ORACLE_HOME -> ${neworaclehome}"
         echo "Starting normal non-RAC Standby Instance ${instname} on ${nodename} to Mount State in new ORACLE_HOME -> ${neworaclehome}" >> ${LOG}
         export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; echo 'startup mount;' | ${neworaclehome}/bin/sqlplus '/ as sysdba'" 
         echo "Running...... ${cmd}"
         echo "Running...... ${cmd}" >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}
		 
         # Check execution of instance/db state was successful
         if [ $? -eq 0 ]; then
            echo "Oracle instance ${instname} on ${nodename} is started, continuing"
            echo "Oracle instance ${instname} on ${nodename} is started, continuing" >> ${LOG}
         else
            echo "Oracle instance ${instname} on ${nodename} did not start, aborting process"
            echo "Oracle instance ${instname} on ${nodename} did not start, aborting process" >> ${LOG}
            exit 8
         fi 
      else
         # Handle RAC 
		 # Update the ORACLE_HOME setting in clusterware
		 # Updating ORACLE_HOME in clusterware
         echo "Updating ORCALE_HOME for ${racdbname} to ${neworaclehome}"
         echo "Updating ORCALE_HOME for ${racdbname} to ${neworaclehome}" >> ${LOG}
		 export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; ${neworaclehome}/bin/srvctl modify database -d ${racdbname} -oraclehome ${neworaclehome}" 
	     ssh -n ${nodename} ${cmd} >> ${LOG}
		 
		 # Check execution of instance/db state was successful
         if [ $? -eq 0 ]; then
            echo "Oracle RAC Database ${racdbname} ORACLE_HOME Change to ${neworaclehome}, continuing"
            echo "Oracle RAC Database ${racdbname} ORACLE_HOME Change to ${neworaclehome}, continuing" >> ${LOG}
         else
            echo "Oracle RAC Database ${racdbname} ORACLE_HOME Change to ${neworaclehome} failed, aborting process"
            echo "Oracle RAC Database ${racdbname} ORACLE_HOME Change to ${neworaclehome} failed, aborting process" >> ${LOG}
            exit 8
         fi 
		 
		 echo "Updating ORCALE_HOME for ${racdbname} to ${neworaclehome}"
         echo "Updating ORCALE_HOME for ${racdbname} to ${neworaclehome}" >> ${LOG}
		 export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${instname}; ${neworaclehome}/bin/srvctl start database -d ${racdbname}" 
	     ssh -n ${nodename} ${cmd} >> ${LOG}

		 # Check execution of instance/db state was successful
         if [ $? -eq 0 ]; then
            echo "Oracle RAC Database ${racdbname} on ${nodename} is started, continuing"
            echo "Oracle RAC Database ${racdbname} on ${nodename} is started, continuing" >> ${LOG}
         else
            echo "Oracle RAC Database ${racdbname} on ${nodename} did not start, aborting process"
            echo "Oracle RAC Database ${racdbname} on ${nodename} did not start, aborting process" >> ${LOG}
            exit 8
         fi 

         echo "---"
         echo "Since this is a RAC Database you will need to update the /etc/oratab on the other nodes in the cluster!"	
         echo "---" >> ${LOG}
         echo "Since this is a RAC Database you will need to update the /etc/oratab on the other nodes in the cluster!"	>> ${LOG}	 
	  fi
   fi

   # If there is a custom glogin.sql that must be moved back in place
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Specified to sleep and wait for number of seconds   
   sleep 30
done < "${inputfile}"

#################################################################
# Run any scripts put in the post patch execution file
if [ -f "${SCRIPTLOC}/${dbpatchupdatepostexec}" ]
 then
echo "Running Post Patch Processes as defined in ${dbpatchupdatepostexec}"
echo "Running Post Patch Processes as defined in ${dbpatchupdatepostexec}" >> ${LOG}
while read -r line_script
do
    ssh -n ${nodename} ${line_script}
done < "${SCRIPTLOC}/${dbpatchupdatepostexec}"
fi

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "ORACLE_HOME Switch for all Databases Complete."
echo "ORACLE_HOME Switch for all Databases Complete." >> ${LOG}

exit 0
