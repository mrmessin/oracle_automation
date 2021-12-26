#######################################################################################################
# ora_deploy_db_patch_update_nonrac.sh
#
# Description: Run qtr deploy patch process for each database in data list
#              for a node
#
# Dependancies:  Process Assumes Oracle non-RAC
#
#                ora_deploy_db_datapatch_non-rolling.sh
#                    Script must be located in the same directory with this script ora_deploy_db_patch_update_nonrac.sh
#
#                ora_deploy_db_patch_update.txt  (${dbpatchupdatefile})  [ora_deploy_db_patch_update_{env}.txt]
#                    Text File containing the main directory where all patches will reside for Patching with Process
#
#                ora_deploy_db_qtrpatch.txt  (${dbpatchfile}) [ora_deploy_db_qtrpatch_{env}.txt]
#                    Text file that contains the qtr patch locations for each patch to be applied for database home
#
#                ora_deploy_db_qtrpatch_nodes_{env}.txt (${inputfile}) can pass as parameter a file with a different node list
#                                       node ORACLE_HOME
#                                       node ORACLE_HOME
#
#                ora_deploy_opatch_batch_rollback.txt [ora_deploy_opatch_batch_rollback_{env}.txt]
#                     List of one off patches applied to the ORACLE_HOME that must be rolled back
#                     this can include patches that may not be applied they will show not present
#                     and check will pass that it is not applied to home and continue.
#
#                ora_deploy_opatch_batch_apply.txt [ora_deploy_opatch_batch_apply_{env}.txt]
#                     List of one-off patches subject to be applied during the patch process
#                     these address one-off issues and are to be applied after bundle patch is applied
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
#               The rolling will require non-use or very low use of the JAVAVM therefore must ensure services
#               Using JAVAVM are off or of low enough utization proces will not impact applications
#               Run on only one of the instances of all all instance homes are patched.
#               Ensure Order in file is the order that the rolling update needs to happen
#
# Is it Used, check all instances for rolling upgrade:
#     select count(*) from x$kglob where KGLOBTYP = 29 OR KGLOBTYP = 56;
# How much is it used:
#   select sess.service_name, sess.username,sess.program, count(*)
#   from
#   v$session sess,
#   dba_users usr,
#   x$kgllk lk,
#   x$kglob
#   where kgllkuse=saddr
#   and kgllkhdl=kglhdadr
#   and kglobtyp in (29,56)
#   and sess.user# = usr.user_id
#   and usr.oracle_maintained = 'N'      -- Omit 11.2.0.4
#   group by sess.service_name, sess.username, sess.program
#   order by sess.service_name, sess.username, sess.program;
#
# Parameters:    environment set to use for paramter files for example
#                pass value of dev and all file parameters become filename${env}.txt
#                if no value passed then filename is filename.txt
#
# Output:  <Script location on file system>/logs/ora_deploy_db_qtrpatch_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_db_patch.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_db_patch.sh <env>
#######################################################################################################
#
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_db_qtrpatch_nodes.txt
# if environment provided then it is ora_deploy_db_qtrpatch_nodes${envinputfile}.txt
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
export LOGFILE=ora_deploy_db_patch_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=ms_us@advizex.com
export EMAIL_LIST=ms_us@advizex.com

echo "###########################################################################################"
echo "###########################################################################################" >> ${LOG}
echo "Checking Parameters and files for Qtr Patch Update Process....."
echo "Checking Parameters and files for Qtr Patch Update Process....." >> ${LOG}

################################################################################################
# Configuration Files for datapatch apply for instances this is standard and not configurable
# is is a fixed list of nodes, instance and dbname to do the post datapatch operation
# the other files for pathfile and patupupdate file are also considered fix, but
# setting the environment variables to other file names will allow those files to be used
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch_nodes.txt
   export dbpatchfile=ora_deploy_db_qtrpatch.txt
   export datapatchinputfile=ora_deploy_db_datapatch.txt
   export dbpatchupdatefile=ora_deploy_db_patch_update.txt
   export dbpatchupdatepreexec=ora_deploy_pre_patch_exec.txt
   export dbpatchupdatepostexec=ora_deploy_post_patch_exec.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch_nodes_${envinputfile}.txt
   export dbpatchfile=ora_deploy_db_qtrpatch_${envinputfile}.txt
   export datapatchinputfile=ora_deploy_db_datapatch_${envinputfile}.txt
   export dbpatchupdatefile=ora_deploy_db_patch_update_${envinputfile}.txt
   export dbpatchupdatepreexec=ora_deploy_pre_patch_exec_${envinputfile}.txt
   export dbpatchupdatepostexec=ora_deploy_post_patch_exec_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process qtr patch update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${dbpatchfile}" ]
 then
   echo "Parameter File Does Not Exist -> ${dbpatchfile} can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${dbpatchfile} can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${datapatchinputfile}" ] 
 then
   echo "Parameter File Does Not Exist -> ${datapatchinputfile} can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${datapatchinputfile} can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${dbpatchupdatefile}" ] 
 then
   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update." >> ${LOG}
   exit 8
fi

# Can add these checks if you wish to ensure that one off patches are to be rolled back and applied
# Otherwise later in process will be skipped if files do not exist
#if [ ! -f "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt" ] 
# then
#   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update."
#   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update." >> ${LOG}
#   exit 8
#fi
#
#if [ ! -f "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt" ] 
# then
#   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update."
#   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update." >> ${LOG}
#   exit 8
#fi

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "${inputfile}"
echo "${inputfile}" >> ${LOG}
echo "${dbpatchfile}"
echo "${dbpatchfile}" >> ${LOG}
echo "${datapatchinputfile}"
echo "${datapatchinputfile}" >> ${LOG}
echo "${dbpatchupdatefile}"
echo "${dbpatchupdatefile}" >> ${LOG}
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
echo "Running Qtr DB Patch for each node/home in ${inputfile}"
echo "Running Qtr DB Patch for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

# Set the PATCHLOCATION (Important to One off Patches)
export PATCHLOCATION=`cat ${SCRIPTLOC}/${dbpatchupdatefile}`
echo ${PATCHLOCATION}
echo ${PATCHLOCATION} >> ${LOG}

#################################################################################
# go through each node in the list in the file and execute upgrade/patching
while read -r line
do 
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export oraclehome=`echo ${line}| awk '{print $2}'`

   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing Oracle HOME for ${nodename} - ${oraclehome}"
   echo "Processing Oracle HOME for ${nodename} - ${oraclehome}" >> ${LOG}

   ###############################################################################################
   # Check if database listener is running in ORACLE_HOME we are patching   
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   # check database listeners running on node for home being switched
   echo "Checking if Status for Listener(s) on ${nodename} in ${oraclehome}"
   echo "Checking if Status for Listener(s) on ${nodename} in ${oraclehome}" >> ${LOG}
   
   export cmd="ps -ef | grep ${oraclehome}/bin/tnslsnr | grep -v grep"
   export listeners=`ssh -n ${nodename} ${cmd}`
   
   # For debuging listener list if needed
   #echo "Listeners Found: ${listeners}"   
   #echo "Listeners Found: ${listeners}" >> ${LOG}

   if [ "${listeners}" = "" ]; then
      echo "No Listeners running on ${oraclehome} skipping listner shutdown......."
   else
      for item in ${listeners}
      do
         ########################################################
         # Assign the Listener name and home for processing
         export listenerhome=`echo ${item}| awk '{print $8}'`
         export listenername=`echo ${item}| awk '{print $9}'`
	  
         echo "Shutting Down Listner ${listnername} running on ${nodename} in ${oraclehome}"
         echo "Shutting Down Listner ${listnername} running on ${nodename} in ${oraclehome}" >> ${LOG}
         export cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/lsnrctl stop ${listenername}"  
         echo "Executing...... ${cmd}"
         echo "Executing...... ${cmd}" >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}
		 
		 if [ $? -eq 0 ]; then
            echo "Shutdown Oracle Listener ${listenername} on ${nodename} Successful"
            echo "Shutdown Oracle Listener ${listenername} on ${nodename} Successful" >> ${LOG}
         else
            echo "Shutdown Oracle Listner ${listenername} on ${nodename} Failed.... aborting process"
            echo "Shutdown Oracle Listner ${listenername} on ${nodename} Failed.... aborting process" >> ${LOG}
            exit 8
         fi
      done
   fi
  
   ###############################################################################################
   # Generate list of running instances for the node for the ORACLE_HOME we are patching   
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Getting List of Databases Running Node ${nodename}"
   echo "Getting List of Databases Running Node ${nodename}" >> ${LOG}
   cmd="ps -ef|grep ora_smon|grep -v grep|awk '{print \$8}'"
   export runningdblist=`ssh -n ${nodename} ${cmd}`
   export runningdblist=`printf '%s\n' "${runningdblist//ora_smon_/}"`

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo "List of Databases running on ${nodename}"
      echo "List of Databases running on ${nodename}" >> ${LOG}
      echo "${runningdblist}"
      echo "${runningdblist}" >> ${LOG}
   else
      echo "List of databases for ${nodename} did not succeed can not continue..."
      echo "List of databases for ${nodename} did not succeed can not continue..." >> ${LOG}
      exit 8
   fi

   # Seed instance list to nothing
   export running_instance_list=''

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   echo "Checking of any running Databases are running from ORACLE_HOME to be patched -> ${oraclehome}"
   echo "Checking of any running Databases are running from ORACLE_HOME to be patched -> ${oraclehome}" >> ${LOG}

   # This check relies on the /etc/oratab bing fully up to date and the dbhome function in /usr/local/bin/dbhome
   # will check for home for database running and see if matches home being patched if so record it as aborting
   # running instance for the home being patched as it will have to be shutdown for patching.
   if [ "${runningdblist}" = "" ]
    then
      echo "No Databases on Server ${nodename} Skipping Check for Runnning Instances"
      echo "No Databases on Server ${nodename} Skipping Check for Runnning Instances" >> ${LOG}
   else
      # Go through each database in cluster check is instance running on node being patched
      for dbname in ${runningdblist}
      do 
         echo "Checking if Status for ${dbname} on ${nodename} for ${oraclehome}"
         echo "Checking if Status for ${dbname} on ${nodename} for ${oraclehome}" >> ${LOG}

         # Check ORACLE_HOME for instance is our oracle home that we are patching
         cmd="echo `/usr/local/bin/dbhome ${dbname}` | grep ${oraclehome}"
         export result=`ssh -n ${nodename} ${cmd}`

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo ""
         else
            echo "Check for running instance for ${dbname} on ${nodename} in ${oraclehome} Failed, aborting......"
            echo "Check for running instance for ${dbname} on ${nodename} in ${oraclehome} Failed, aborting......" >> ${LOG}
            exit 8
         fi

         if [ "${result}" = "" ]
          then
            echo "Skipping Database ${dbname} not using home being patched -> ${oraclehome}"
            echo "Skipping Database ${dbname} not using home being patched -> ${oraclehome}" >> ${LOG}
         else
            echo "Recording instance ${dbname} into nodes running instance list using home being patched."
            echo "Recording instance ${dbname} into nodes running instance list using home being patched." >> ${LOG}

            # Instance ok then record in running instance list
            export running_instance_list=`echo -e "${running_instance_list}\n${dbname}"`
         fi
      done
   fi

   echo "${running_instance_list}"
   echo "${running_instance_list}" >> ${LOG}

   if [ "${running_instance_list}" = "" ]
    then
       echo "No Running Instances Running in ${oraclehome} on Server ${nodename} No Instances to Shutdown to patch the home"
       echo "No Running Instances Running in ${oraclehome} on Server ${nodename} No Instances to Shutdown to patch the home" >> ${LOG}
   else
      ###############################################################################################
      # Shutdown instances in instance list
      ###############################################################################################
      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Shutting down instances ${running_instance_list} on ${nodename}."
      echo "Shutting down instances ${running_instance_list} on ${nodename}." >> ${LOG}
   
      #Set the field separator to new line
      IFS=$'\n'

      ###############################################################################################################
      # Loop through the running instance list and execute a shutdown for each running out of the home being patched
      for db in `echo -e "${running_instance_list}"`
      do
         echo "Shutting down database ${db} instance on ${nodename}"
         echo "Shutting down database ${db} instance on ${nodename}" >> ${LOG}

         export cmd="export ORACLE_HOME=${oraclehome}; export ORACLE_SID=${db}; echo -e 'shutdown immediate;' | sqlplus 'as sysdba'"
         ssh -n ${nodename} ${cmd} >> ${LOG}

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo "Oracle database ${db} on ${nodename} Shutdown"
            echo "Oracle database ${db} on ${nodename} Shutdown" >> ${LOG}
         else
            echo "Oracle database ${db} on ${nodename} Shutdown Failed, aborting....."
            echo "Oracle database ${db} on ${nodename} Shutdown Failed, aborting....." >> ${LOG}
            exit 8
         fi
      done 
   fi

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
 
   #######################################################################
   # execute any pre scripts to patching before do shutdown of databases
   # running in the oracle home we are patching
   if [ -f "${SCRIPTLOC}/${dbpatchupdatepreexec}" ] 
    then
      echo "Executing prepatch scripts as indicated in ${dbpatchupdatepreexec}"
      echo "Executing prepatch scripts as indicated in ${dbpatchupdatepreexec}" >> ${LOG}
      echo ${dbpatchupdatepreexec}
      echo ${dbpatchupdatepreexec} >> ${LOG}

      while read -r line_script
      do
         ssh -n ${nodename} ${line_script}
      done < "${SCRIPTLOC}/${dbpatchupdatepreexec}"
   else
      echo "Prepatch Execution Step file ${dbpatchupdatepreexec} Not Found."
      echo "Prepatch Execution Step file ${dbpatchupdatepreexec} Not Found." >> ${LOG}
      echo "No prepatch scripts to be executed......"
      echo "No prepatch scripts to be executed......" >> ${LOG}
   fi

   ###############################################################################################
   # Check if lsof is any processes run with files from ORACLE_HOME being patched
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Checking if any files in the ORACLE_HOME - ${oraclehome} are in use......"
   echo "Checking if any files in the ORACLE_HOME - ${oraclehome} are in use......" >> ${LOG}
   cmd="/usr/sbin/lsof | grep ${oraclehome}"

   # Initialize result
   export result=""
   export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

   # Check the patch result check
   if [ "${result}" = "" ]; then
      echo "No Processes running with Files in ORACLE_HOME - ${oraclehome} will continue...."
      echo "No Processes running with Files in ORACLE_HOME - ${oraclehome} will continue...." >> ${LOG}
   else
      echo "Processes running with Files in ORACLE_HOME - ${oraclehome} Aborting...."
      echo "Processes running with Files in ORACLE_HOME - ${oraclehome} Aborting...." >> ${LOG}
      echo "Will Need to Restart all databases for ${nodename} before rerunning process"
      echo "Will Need to Restart all databases for ${nodename} before rerunning process" >> ${LOG}
      exit 8
   fi

   ###############################################################################################
   # Rollback All One Off Patches
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   # Check if any one off patches to rollback
   if [ -f "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt" ] 
    then
      echo "Rolling Back One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}"  
      echo "Rolling Back One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}" >> ${LOG}
      cat ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt
      cat ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt >> ${LOG}
   
      # Execute rollback process requires list of patch in file ora_deploy_opatch_batch_rollback.txt as list of patches to rollback
      #
      # go through each node in the list in the file and execute patch rollback for each patch to HOME
      while read -r line
      do
         # Set patch number from line in file
         export PATCHNUMBER=${line}

         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------"
         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------" >> ${LOG}
         echo "Rolling back Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Rolling back Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/opatch rollback -id ${PATCHNUMBER} -silent"
         #echo ${cmd}
         #echo ${cmd} >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}

         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/opatch lsinventory | grep ${PATCHNUMBER}"
         echo ${cmd}
         echo ${cmd} >> ${LOG}
      
         # Initialize result
         export result=""
         export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

         # Check the patch result check
         if [ "${result}" != "" ]; then
           echo "ERROR -> Patch Rollback Verification Failed for ${PATCHNUMBER} on ${nodename}"
           echo "ERROR -> Patch Rollback Verification Failed for ${PATCHNUMBER} on ${nodename}" >> ${LOG}
           #exit 8
         else
            echo "Patch Rollback Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
            echo "Patch Rollback Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         fi
      done < "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt"
   else
      echo "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt file not found for one off patches."
	  echo "Skipping rollback of one off patches"
      echo "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt file not found for one off patches." >> ${LOG}
	  echo "Skipping rollback of one off patches" >> ${LOG}
   fi

   ###############################################################################################
   # Apply Patch to Database Home
   ###############################################################################################
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Applying Database Home Patch(es) on ${nodename} for ORACLE_HOME ${oraclehome}"  
   echo "Applying Database Home Patch(es) on ${nodename} for ORACLE_HOME ${oraclehome}" >> ${LOG}

   # Execute Process to Apply patches from the ${dbpatchfile} file which lists patch directory patchexec user
   while read -r line
   do 
      export patchlocation=`echo ${line}| awk '{print $1}'`
      export patchutil=`echo ${line}| awk '{print $2}'`
      export execowner=`echo ${line}| awk '{print $3}'`

      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Executing Patch ${patchlocation} for ${oraclehome} on ${nodename} using ${patchutil} as ${execowner}"
      echo "Executing Patch ${patchlocation} for ${oraclehome} on ${nodename} using ${patchutil} as ${execowner}" >> ${LOG}

      if [ "${execowner}" != "root" ]
       then
         cmd="export ORACLE_HOME=${oraclehome}; cd ${patchlocation}; ${oraclehome}/OPatch/${patchutil} apply -silent"
      else
         cmd="sudo su -c 'export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/${patchutil} apply ${patchlocation} -oh ${oraclehome} -ocmrf /u01/app/oracle/software/ocm.rsp'"
      fi
         
      echo "Executing Patch Command:"
      echo "Executing Patch Command:" >> ${LOG}
      echo ${cmd}
      echo ${cmd} >> ${LOG}

      # Execute the patch apply on the remote node
      ssh -tt -n ${nodename} ${cmd} >> ${LOG}

      # May need to put in opatch lsinventory grep for post check as warnings may cause command check to fail.
      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database patch ${patchlocation} on ${nodename} Successful"
         echo "Oracle database patch ${patchlocation} on ${nodename} Successful" >> ${LOG}
      else
         echo "Oracle database patch ${patchlocation} on ${nodename} Failed, aborting...."
         echo "Oracle database patch ${patchlocation} on ${nodename} Failed, aborting...." >> ${LOG}
         #exit 8
      fi
   done < "${SCRIPTLOC}/${dbpatchfile}"

   ###############################################################################################
   # Apply All One Off Patches if we have them
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   # Check if any one off patches to rollback
   if [ -f "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt" ] 
    then
      echo "Applying One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}"  
      echo "Applying One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}" >> ${LOG}
      cat ${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt
      cat ${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt >> ${LOG}

      # Execute apply process requires list of patch in file ora_deploy_opatch_batch_apply.txt as list of patches to apply
      #
      # go through each node in the list in the file and execute patch apply for each patch to HOME
      while read -r line
      do
         # Set patch number from line in file
         export PATCHNUMBER=${line}

         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------"
         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------" >> ${LOG}
         echo "Applying Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Applying Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="cd ${PATCHLOCATION}/${PATCHNUMBER}; ${oraclehome}/OPatch/opatch apply -silent -ocmrf /u01/app/oracle/software/ocm.rsp"
         #echo ${cmd}
         #echo ${cmd} >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}

         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/opatch lsinventory | grep ${PATCHNUMBER}"
         #echo ${cmd}
         echo ${cmd} >> ${LOG}

         # initialize result
         export result=""
         export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

         # Check the patch result check
         if [ "${result}" = "" ]; then
            echo "ERROR -> Patch Apply Not verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
            echo "ERROR -> Patch Apply Not verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
            #exit 8
         else
            echo "Patch Apply Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
            echo "Patch Apply Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         fi
      done < "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt"
   else
      echo "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt file not found for one off patches."
      echo "Skipping apply of one off patches"
      echo "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt file not found for one off patches." >> ${LOG}
      echo "Skipping apply of one off patches" >> ${LOG}
   fi

   ###############################################################################################
   # Check if database listener is needs restarted in ORACLE_HOME we are patching   
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   if [ "${listeners}" = "" ]; then
      echo "No Listeners running on ${oraclehome} skipping listener start......."
   else
      for item in ${listeners}
      do
         ########################################################
         # Assign the Listener name and home for processing
         export listenerhome=`echo ${item}| awk '{print $8}'`
         export listenername=`echo ${item}| awk '{print $9}'`
	  
         echo "Shutting Down Listner ${listnername} running on ${nodename} in ${oraclehome}"
         echo "Shutting Down Listner ${listnername} running on ${nodename} in ${oraclehome}" >> ${LOG}
         export cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/lsnrctl start ${listenername}"  
         echo "Executing...... ${cmd}"
         echo "Executing...... ${cmd}" >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}
		 
		 if [ $? -eq 0 ]; then
            echo "Start Oracle Listener ${listenername} on ${nodename} Successful"
            echo "Start Oracle Listener ${listenername} on ${nodename} Successful" >> ${LOG}
         else
            echo "Start Oracle Listner ${listenername} on ${nodename} Failed...."
            echo "Start Oracle Listner ${listenername} on ${nodename} Failed...." >> ${LOG}
            #exit 8
         fi
      done
   fi
   
   ###############################################################################################
   # Startup database instances on Node for ORACLE_HOME being patched
   # Assumes /etc/oratab is up to date and has instance names in there
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   if [ "${running_instance_list}" = "" ]
    then
       echo "No Instances were Running at Patching Start in ${oraclehome} on Server ${nodename} No Instances to Re-Start for ${oraclehome}"
       echo "No Instances were Running at Patching Start in ${oraclehome} on Server ${nodename} No Instances to Re-Start for ${oraclehome}" >> ${LOG}
   else
      echo "Starting instances ${running_instance_list} on ${nodename}."
      echo "Starting instances ${running_instance_list} on ${nodename}." >> ${LOG}

      for db in ${running_instance_list}
      do
         echo "Starting database ${db} on ${nodename}"
         echo "Starting database ${db} on ${nodename}" >> ${LOG}

         export cmd="export ORACLE_HOME=${oraclehome}; export ORACLE_SID=${db}; echo -e 'startup;' | sqlplus 'as sysdba'"
         ssh -n ${nodename} ${cmd} >> ${LOG}

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Started"
            echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Started" >> ${LOG}
         else
            echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Start Failed, aborting....."
            echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Start Failed, aborting....." >> ${LOG}
            exit 8
         fi
      done
   fi

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "ORACLE_HOME Patching for node ${nodename} for ORACLE_HOME ${oraclehome} Complete."
   echo "ORACLE_HOME Patching for node ${nodename} for ORACLE_HOME ${oraclehome} Complete." >> ${LOG}
   echo "--" >> ${LOG}
   echo "--" >> ${LOG}
   echo "--"
   echo "--"
   
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   if [ "${running_instance_list}" = "" ]
    then
       echo "No Instances were Running in ${oraclehome} on Server ${nodename} No Instances to Datapatch for ${oraclehome} skipping Datapatch"
       echo "No Instances were Running in ${oraclehome} on Server ${nodename} No Instances to Datapatch for ${oraclehome} skipping Datapatch" >> ${LOG}
   else
      ###############################################################################################################
      # Do datapatch for node completed using the running instance list
      ###############################################################################################################
      echo "Executing Datapatch for the node ${nodename} for patching process"
      echo "Executing Datapatch for the node ${nodename} for patching process" >> ${LOG}
      echo "Writing the ora_deploy_db_datapatch.txt from running instance list for node ${nodename}"
      echo "Writing the ora_deploy_db_datapatch.txt from running instance list for node ${nodename}" >> ${LOG}

      # First remove file that we are going to use
      rm -f ${SCRIPTLOC}/ora_deploy_db_datapatch_temp.txt
   
      ###############################################################################################################
      # create a file we can use to control with node name and running instance list for the process
      # we are calling using the default file name for the process -> ora_deploy_db_datapatch.txt
      # Loop through the running instance list and execute a shutdown for each running out of the home being patched
      for db in `echo -e "${running_instance_list}"`
       do
         echo "${nodename}   ${db}" >> ora_deploy_db_datapatch_temp.txt

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo "Oracle database ${db} on ${nodename} Shutdown"
            echo "Oracle database ${db} on ${nodename} Shutdown" >> ${LOG}
         else
            echo "Oracle database ${db} on ${nodename} Shutdown Failed, aborting....."
            echo "Oracle database ${db} on ${nodename} Shutdown Failed, aborting....." >> ${LOG}
            exit 8
         fi
      done 
   
      # Run the datapatch for the list of running instances we created
      ${SCRIPTLOC}/ora_deploy_datapatch_non-rolling.sh ${SCRIPTLOC}/ora_deploy_db_datapatch_temp.txt

      # remove file that we used as we are finished
      rm -f ${SCRIPTLOC}/ora_deploy_db_datapatch_temp.txt
   fi

   #################################################################
   # Place this after any patching processing for a node
   if [ -f "${SCRIPTLOC}/${dbpatchupdatepostexec}" ] 
    then
      while read -r line_script
      do
       ssh -n ${nodename} ${line_script}
      done < "${SCRIPTLOC}/${dbpatchupdatepostexec}"
   fi
   
   # Specified to sleep and wait for number of seconds   
   sleep 10
done < "${inputfile}"

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "ORACLE_HOME Patching for all ORACLE_HOMEs ${oraclehome} Complete."
echo "ORACLE_HOME Patching for all ORACLE_HOMEs ${oraclehome} Complete." >> ${LOG}

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "Qtr DB Patch Update Process Complete!"
echo "Qtr DB Patch Update Process Complete!" >> ${LOG}

exit 0
