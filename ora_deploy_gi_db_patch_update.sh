#######################################################################################################
# ora_deploy_gi_db_qtrpatch_update.sh
#
# Description: Run qtr deploy patch process for each grid infrastructure and database for RAC Cluster
#
# Dependancies:  Process Assumes Oracle RAC and Rolling Update
#
#             Default
#                ora_deploy_gi_qtrpatch.txt {${patchfile}) [ora_deploy_gi_qtrpatch_{env}.txt]
#                    Text file that contains the qtr patch locations for each patch to be applied for database home
#
#                ora_deploy_gi_db_qtrpatch_nodes.txt (${inputfile})  [ora_deploy_gi_db_qtrpatch_nodes_{env}.txt]
#                                       node GIORACLE_HOME DBORACLE_HOME
#                                       node GIORACLE_HOME DBORACLE_HOME
#
#                ora_deploy_db_patch_update.txt  {${dbpatchupdatefile})  [ora_deploy_db_patch_update_{env}.txt]
#                    Text File containing the main directory where all patches will reside for Patching with Process
#
#                ora_deploy_db_qtrpatch.txt  (${dbpatchfile}) [ora_deploy_db_qtrpatch_{env}.txt]
#                    Text file that contains the qtr patch locations for each patch to be applied for database home
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
#            Custom
#               Use all files names in detault, but append a custom environment indicator, for example _qap
#                ora_deploy_gi_qtrpatch_qap.txt
#                ora_deploy_gi_db_qtrpatch_nodes_{env}.txt (${inputfile}) can pass as parameter a file with a different node list
#                ora_deploy_db_patch_update_qap.txt
#                ora_deploy_db_qtrpatch_qap.txt
#
#            Required                  
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
#                if no value passed then see defaults above
#
# Output:  <Script location on file system>/logs/ora_deploy_gi_db_qtrpatch_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_gi_db_qtrpatch.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_gi_db_qtrpatch.sh <env>
#######################################################################################################
#
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_db_qtrpatch_nodes.txt
# if environment provided then it is ora_deploy_db_qtrpatch_nodes$_{envinput}.txt
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
export LOGFILE=ora_deploy_gi_db_qtrpatch_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

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
   # GI
   export patchfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch.txt
   # GI/DB
   export inputfile=${SCRIPTLOC}/ora_deploy_gi_db_qtrpatch_nodes.txt
   # DB
   export dbpatchfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch.txt
   export datapatchinputfile=${SCRIPTLOC}/ora_deploy_db_datapatch.txt
   export dbpatchupdatefile=${SCRIPTLOC}/ora_deploy_db_patch_update.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   #GI
   export patchfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch_${envinputfile}.txt
   # GI/DB
   export inputfile=${SCRIPTLOC}/ora_deploy_gi_db_qtrpatch_nodes_${envinputfile}.txt
   # DB
   export dbpatchfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch_${envinputfile}.txt
   export datapatchinputfile=${SCRIPTLOC}/ora_deploy_db_datapatch_${envinputfile}.txt
   export dbpatchupdatefile=${SCRIPTLOC}/ora_deploy_db_patch_update_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
########################
# GI Input Validation
########################
if [ -z "${patchfile}" ]
then
   echo "No Patch List File Provided ${patchfile} can not proceed with gi patching"
   echo "No Patch List File Provided ${patchfile} can not proceed with gi patching" >> ${LOG}
   exit 8
fi   

###########################
# GI/DB Input Validation
###########################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process GI/DB patch update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process GI/DB patch update." >> ${LOG}
   exit 8
fi

########################
# DB Input Validation
########################
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

if [ ! -f "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt" ] 
 then
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt" ] 
 then
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt can not process qtr patch update." >> ${LOG}
   exit 8
fi

echo "#################################################################################################"
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "Node/Home List File -> ${inputfile}"
echo "Node/Home List File -> ${inputfile}" >> ${LOG}
echo "GI Patch File -> ${patchfile}"
echo "GI Patch File -> ${patchfile}" >> ${LOG}
echo "DB Patch File -> ${dbpatchfile}"
echo "DB Patch File -> ${dbpatchfile}" >> ${LOG}
echo "DataPatch File -> ${datapatchinputfile}"
echo "DataPatch File -> ${datapatchinputfile}" >> ${LOG}
echo "DataPatch Update File -> ${dbpatchupdatefile}"
echo "DataPatch Update File -> ${dbpatchupdatefile}" >> ${LOG}
echo "One-Off Rollback Patch List File -> ora_deploy_opatch_batch_rollback.txt"
echo "One-Off Rollback Patch List File -> ora_deploy_opatch_batch_apply.txt"

# Set Local hostname
export HOSTNAME=`hostname`
echo ${HOSTNAME}
echo ${HOSTNAME} >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running GI Patching and DB Patching for each node/home in ${inputfile}"
echo "Running GI Patching and DB Patching for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}
echo "-"

# Set the DBONEOFFPATCHLOCATION (Important to One off Patches)
export DBONEOFFPATCHLOCATION=`cat ${SCRIPTLOC}/${dbpatchupdatefile}`
echo "DB One Off Patch Base Location -> ${DBONEOFFPATCHLOCATION}"
echo "DB One Off Patch Base Location -> ${DBONEOFFPATCHLOCATION}" >> ${LOG}

# We are Just starting at first node (can set for non-prod to N so only 60 second pause)
export first_node="Y"
#export first_node="N"

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export gioraclehome=`echo ${line}| awk '{print $2}'`
   export dboraclehome=`echo ${line}| awk '{print $3}'`

   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing GI Oracle HOME for ${nodename} - ${gioraclehome}"
   echo "Processing GI Oracle HOME for ${nodename} - ${gioraclehome}" >> ${LOG}
   echo "Processing DB Oracle HOME for ${nodename} - ${dboraclehome}"
   echo "Processing DB Oracle HOME for ${nodename} - ${dboraclehome}" >> ${LOG}

   ###############################################################################################
   # Generate list of running instances for the node in the DB ORACLE_HOME we are patching  
   # We want to shut these down prior to beginning patching so that way they are down and 
   # We can move from GI Patch to database patch immediately and not have instances
   # come back up post GI Patching   
   ###############################################################################################
   # List of databases in cluster
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Getting List of Databases for RAC Cluster for DB ORACLE_HOME ${dboraclehome}"
   echo "Getting List of Databases for RAC Cluster for DB ORACLE_HOME ${dboraclehome}" >> ${LOG}
   cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl config database"
   export dblist=`ssh -n ${nodename} ${cmd}`

   # Check if issue with last command
   if [ $? -eq 0 ]; then
      echo "List of Databases in RAC Cluster"
      echo "List of Databases in RAC Cluster" >> ${LOG}
      echo "${dblist}"
      echo "${dblist}" >> ${LOG}
   else
      echo "List of databases for ${nodename} did not succeed can not continue may not be a RAC Cluster..."
      echo "List of databases for ${nodename} did not succeed can not continue may not be a RAC Cluster..." >> ${LOG}
      exit 8
   fi

   # Seed instance list to nothing
   export running_instance_list=''

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   if [ "${dblist}" = "" ]
    then
      echo "No Running Databases on Server ${nodename} Skipping Check for Runnning Instances"
      echo "No Running Databases on Server ${nodename} Skipping Check for Runnning Instances" >> ${LOG}
   else
      # Go through each database in cluster check is instance running on node being patched
      for dbname in ${dblist}
      do 
         echo "Checking if Status for ${dbname} on ${nodename}"
         echo "Checking if Status for ${dbname} on ${nodename}" >> ${LOG}

         # Check ORACLE_HOME for instance is our oracle home that we arer patching
         cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl config database -d ${dbname} | grep ${dboraclehome}"
         export result=`ssh -n ${nodename} ${cmd}`

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo ""
         else
            echo "Check for running instance on ${nodename} in ${dboraclehome} Failed, aborting......"
            echo "Check for running instance on ${nodename} in ${dboraclehome} Failed, aborting......" >> ${LOG}
            exit 8
         fi

         if [ "${result}" = "" ]
          then
            echo "Skipping Database ${dbname} not using the patching home ${dboraclehome}"
            echo "Skipping Database ${dbname} not using the patching home ${dboraclehome}" >> ${LOG}
         else
            # from that list check that there is a running instance on the node
            # loop through the database list for the cluster checking for instance on node
            cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl status database -d ${dbname} | grep 'is running on node ${nodename}'"
            export result=`ssh -n ${nodename} ${cmd}`

            # if not null then we have a running instance
            if [ "${result}" = "" ]; then
               # Skipping the instance on node not running there
               echo "Skipping Database ${dbname} not running on node ${nodename}"
               echo "Skipping Database ${dbname} not running on node ${nodename}" >> ${LOG}
            else  
               # Running instance for databse exists on node being patched.
               export instancename=`echo ${result}| awk '{print $2}'`

               echo "Recording instance ${instancename} for ${dbname} into nodes running instance list."
               echo "Recording instance ${instancename} for ${dbname} into nodes running instance list." >> ${LOG}

               # Instance ok then record in running instance list
               export running_instance_list=`echo -e "${running_instance_list}\n${dbname} ${instancename}"`
            fi
         fi
      done
   fi

   echo "Getting Running instance list for ${nodename} succeeded"
   echo "Getting Running instance list for ${nodename} succeeded" >> ${LOG}
   echo "${running_instance_list}"
   echo "${running_instance_list}" >> ${LOG}

   if [ "${running_instance_list}" = "" ]
    then
       echo "No Running Instances on Server ${nodename} No Instances to Shutdown"
       echo "No Running Instances on Server ${nodename} No Instances to Shutdown" >> ${LOG}
   else
      ###############################################################################################
      # Shutdown and disable instances in running instance list for node
      ###############################################################################################
      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Shutting down and disable instances ${running_instance_list} on ${nodename}."
      echo "Shutting down and disable instances ${running_instance_list} on ${nodename}." >> ${LOG}
      echo "${running_instance_list}"

      #Set the field separator to new line
      IFS=$'\n'

      for db in `echo -e "${running_instance_list}"`
      do
         export actiondbname=`echo ${db}| awk '{print $1}'`
         export actioninstancename=`echo ${db}| awk '{print $2}'`

         echo "Shutting down database ${actiondbname} instance ${actioninstancename} on ${nodename}"
         echo "Shutting down database ${actiondbname} instance ${actioninstancename} on ${nodename}" >> ${LOG}

         export cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl stop instance -d ${actiondbname} -i ${actioninstancename} -force"
         ssh -n ${nodename} ${cmd}

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown"
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown" >> ${LOG}
         else
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown Failed, aborting....."
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown Failed, aborting....." >> ${LOG}
            exit 8
         fi
		 
         export cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl disable instance -d ${actiondbname} -i ${actioninstancename}"
         ssh -n ${nodename} ${cmd}

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Disabled"
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Disabled" >> ${LOG}
         else
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Disable Failed, aborting....."
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Disable Failed, aborting....." >> ${LOG}
            exit 8
         fi
      done 
   fi

   ###############################################################################################
   # Apply Patches to GI HOME
   ###############################################################################################
   echo "Applying Patches to GI Home -> ${gioraclehome}"
   cat ${patchfile}
   cat ${patchfile} >> ${LOG}

   # Execute Process to Apply patches from the ora_deploy_gi_qtrpatch.txt file which lists patch directory patchexec user
   while read -r line2
   do 
      export patchlocation=`echo ${line2}| awk '{print $1}'`
      export patchutil=`echo ${line2}| awk '{print $2}'`
      export execowner=`echo ${line2}| awk '{print $3}'`

      echo "----------------------------------------------------------------------------------------------"
      echo "----------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Executing Patch ${patchlocation} for ${gioraclehome} on ${nodename} using ${patchutil} as ${execowner}"
      echo "Executing Patch ${patchlocation} for ${gioraclehome} on ${nodename} using ${patchutil} as ${execowner}" >> ${LOG}

      ###########################################################################################################################
      # FUTURE CHECK FOR PATH ALREADY APPLIED THERE ARE MULTIPLE PATCHES HOW DO DO THIS CHECK MAYBE ANOTHER CONFIG THAT LISTS
      # check of the patch is already applied on the remote node if it is we can skip it
      #echo "Checking if Patch ${patchlocation} for ${oraclehome} on ${nodename} is already applied."
      #echo "Checking if Patch ${patchlocation} for ${oraclehome} on ${nodename} is already applied." >> ${LOG}
      #cmd="export ORACLE_HOME=${oraclehome}; cd ${patchlocation}; ${oraclehome}/OPatch/opatch lsinventory | grep patch"
      #echo ${cmd}
   
      # Execute the patch apply on the remote node
      #export results=`ssh -n ${nodename} ${cmd} `
      #echo ${results}
      #echo ${results| >> ${LOG}
      ###########################################################################################################################
      
      # Determine if a root or non-root patch execution    
      if [ "${execowner}" != "root" ]
       then
         cmd="export ORACLE_HOME=${gioraclehome}; cd ${patchlocation}; ${gioraclehome}/OPatch/${opatchutil} apply"
      else
         cmd="sudo su -c 'export ORACLE_HOME=${gioraclehome}; ${gioraclehome}/OPatch/${patchutil} apply ${patchlocation} -oh ${gioraclehome}'"
      fi
   
      # Show the patch command being executed will help for troubleshooting any issues.      
      echo "Executing Patch Command:"
      echo "Executing Patch Command:" >> ${LOG}
      echo ${cmd}
      echo ${cmd} >> ${LOG}

      # Execute the patch apply on the remote node
      ssh -n -tt ${nodename} ${cmd} >> ${LOG}
      #ssh -n ${nodename} ${cmd} >> ${LOG}

      ###########################################################################################################################
      # FUTURE MAY WANT TO CHANGE POST CHECK TO MATCH PRECHECK TO MAKE SURE PATHES ARE APPLIED 
      # AS WARNINGS WOULD CAUSE ABORT OF PATCHING PROCESS AND THIS MAY NOT BE WHAT WE WANT
      ###########################################################################################################################

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle GI patch ${patchlocation} on ${nodename} for ${gioraclehome} Successful"
         echo "Oracle GI patch ${patchlocation} on ${nodename} for ${gioraclehome} Successful" >> ${LOG}
      else
         echo "Oracle database patch ${patchlocation} on ${nodename} for ${gioraclehome} Failed, aborting...."
         echo "Oracle database patch ${patchlocation} on ${nodename} for ${gioraclehome} Failed, aborting...." >> ${LOG}
         exit 8
      fi
   done < "${patchfile}"
   
   ###############################################################################################
   # Check if lsof is any processes run with files from ORACLE_HOME being patched
   ###############################################################################################
   echo "Checking if any files in the DB ORACLE_HOME - ${dboraclehome} are in use before continuing......"
   echo "Checking if any files in the DB ORACLE_HOME - ${dboraclehome} are in use before continuing......" >> ${LOG}
   cmd="lsof | grep ${dboraclehome}"

   # Initialize result
   export result=""
   export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

   # Check the patch result check
   if [ "${result}" = "" ]; then
      echo "No Processes running with Files in ORACLE_HOME - ${dboraclehome} will continue...."
      echo "No Processes running with Files in ORACLE_HOME - ${dboraclehome} will continue...." >> ${LOG}
   else
      echo "Processes running with Files in ORACLE_HOME - ${dboraclehome} Aborting...."
      echo "Processes running with Files in ORACLE_HOME - ${dboraclehome} Aborting...." >> ${LOG}
      echo "Will Need to Restart and re-enable all databases for ${nodename} before rerunning process"
      echo "Will Need to Restart and re-enable all databases for ${nodename} before rerunning process" >> ${LOG}
	  echo "Can at this point if GI Patch is already Completed OK can just run DB Patch Automated Update Proces once issue resolved."
	  echo "Can at this point if GI Patch is already Completed OK can just run DB Patch Automated Update Proces once issue resolved." >> ${LOG}
      exit 8
   fi

   ###############################################################################################
   # Rollback All One Off Patches for DB Home
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Rolling Back One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${dboraclehome}"  
   echo "Rolling Back One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${dboraclehome}" >> ${LOG}
   cat ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt
   cat ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt >> ${LOG}
   
   # Execute rollback process requires list of patch in file ora_deploy_opatch_batch_rollback.txt as list of patches to rollback
   #
   # go through each node in the list in the file and execute patch rollback for each patch for HOME
   while read -r line
   do
      # Set patch number from line in file
      export PATCHNUMBER=${line}

      echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------"
      echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------" >> ${LOG}
      echo "Rolling back Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
      echo "Rolling back Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
      cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/OPatch/opatch rollback -id ${PATCHNUMBER} -silent"
      echo ${cmd}
      echo ${cmd} >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      echo "Checking status of Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
      echo "Checking status of Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
      cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/OPatch/opatch lsinventory | grep ${PATCHNUMBER}"
      echo ${cmd}
      echo ${cmd} >> ${LOG}
      
      # Initialize result
      export result=""
      export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

      # Check the patch result check
      if [ "${result}" != "" ]; then
        echo "ERROR -> Patch Rollback Verification Failed for ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
        echo "ERROR -> Patch Rollback Verification Failed for ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
        #exit 8
      else
         echo "Patch Rollback Verified for patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
         echo "Patch Rollback Verified for patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
      fi
   done < "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt"

   ###############################################################################################
   # Apply Patch(es) to Database Home
   ###############################################################################################
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Applying Database Home Patch on ${nodename} for ORACLE_HOME ${dboraclehome}"  
   echo "Applying Database Home Patch on ${nodename} for ORACLE_HOME ${dboraclehome}" >> ${LOG}

   # Execute Process to Apply patches from the ${dbpatchfile} file which lists patch directory patchexec user
   while read -r line
   do 
      export patchlocation=`echo ${line}| awk '{print $1}'`
      export patchutil=`echo ${line}| awk '{print $2}'`
      export execowner=`echo ${line}| awk '{print $3}'`

      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Executing Patch ${patchlocation} for ${dboraclehome} on ${nodename} using ${patchutil} as ${execowner}"
      echo "Executing Patch ${patchlocation} for ${dboraclehome} on ${nodename} using ${patchutil} as ${execowner}" >> ${LOG}

      if [ "${execowner}" != "root" ]
       then
         cmd="export ORACLE_HOME=${dboraclehome}; cd ${patchlocation}; ${dboraclehome}/OPatch/${patchutil} apply -silent -local"
      else
         cmd="sudo su -c 'export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/OPatch/${patchutil} apply ${patchlocation} -oh ${dboraclehome} -ocmrf /u01/app/oracle/software/ocm.rsp'"
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
         echo "Oracle database patch ${patchlocation} on ${nodename} for ${dboraclehome} Successful"
         echo "Oracle database patch ${patchlocation} on ${nodename} for ${dboraclehome} Successful" >> ${LOG}
      else
         echo "Oracle database patch ${patchlocation} on ${nodename} for ${dboraclehome} Failed, aborting...."
         echo "Oracle database patch ${patchlocation} on ${nodename} for ${dboraclehome} Failed, aborting...." >> ${LOG}
         exit 8
      fi
   done < "${SCRIPTLOC}/${dbpatchfile}"

   ###############################################################################################
   # Apply All One Off Patches
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Applying One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${dboraclehome}"  
   echo "Applying One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${dboraclehome}" >> ${LOG}
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
      echo "Applying Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
      echo "Applying Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
      cmd="cd ${DBONEOFFPATCHLOCATION}/${PATCHNUMBER}; export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/OPatch/opatch apply -silent -ocmrf /u01/app/oracle/software/ocm.rsp"
      echo ${cmd}
      echo ${cmd} >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      echo "Checking status of Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
      echo "Checking status of Patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
      cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/OPatch/opatch lsinventory | grep ${PATCHNUMBER}"
      echo ${cmd}
      echo ${cmd} >> ${LOG}

      # initialize result
      export result=""
      export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

      # Check the patch result check
      if [ "${result}" = "" ]; then
         echo "ERROR -> Patch Apply Not verified for patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
         echo "ERROR -> Patch Apply Not verified for patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
         #exit 8
      else
         echo "Patch Apply Verified for patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}"
         echo "Patch Apply Verified for patch ${PATCHNUMBER} for ${dboraclehome} on ${nodename}" >> ${LOG}
      fi
   done < "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt"

   ###############################################################################################
   # Enable and Startup database instances on Node for ORACLE_HOME being patched
   # Assumes /etc/oratab is up to date and has instance names in there
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Starting instances ${running_instance_list} on ${nodename}."
   echo "Starting instances ${running_instance_list} on ${nodename}." >> ${LOG}

   for db in ${running_instance_list}
   do
      export actiondbname=`echo ${db}| awk '{print $1}'`
      export actioninstancename=`echo ${db}| awk '{print $2}'`

      echo "Enabling and Starting database ${actiondbname} instance ${actioninstancename}"
      echo "Enabling and Starting database ${actiondbname} instance ${actioninstancename}" >> ${LOG}

      export cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl enable instance -d ${actiondbname} -i ${actioninstancename}"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Enabled"
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Enabled" >> ${LOG}
      else
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Enable Failed, aborting....."
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Enable Failed, aborting....." >> ${LOG}
         exit 8
      fi

      # For standby databases with open read only and multiple instances we were seeing errors so mount databases 
      # then once mounted then check if physical standby if so then do nothing if Primary then open.	  
      export cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl start instance -d ${actiondbname} -i ${actioninstancename} -o mount"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Mounted"
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Mounted" >> ${LOG}
      else
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Mount Failed, aborting....."
         echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Mount Failed, aborting....." >> ${LOG}
         exit 8
      fi

      # Check if physical Standby if so then no action otherwise we should attempt to open database
      export cmd="export ORACLE_HOME=${dboraclehome}; export ORACLE_SID=${actioninstancename}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select database_role from v\$database;' | ${dboraclehome}/bin/sqlplus -s '/ AS SYSDBA'"
      export result=`ssh -n ${nodename} ${cmd} `
      echo "${result}" >> ${LOG}
      echo "${result}"

      if [ "${result}" != "PHYSICAL STANDBY" ]
       then
          # Since not a physical stadby lets open the database
          echo "Not Physical Standby Opening -> ${nodename} - ${actiondbname} - ${actioninstancename}...."
          echo "Not Physical Standby Opening -> ${nodename} - ${actiondbname} - ${actioninstancename}...." >> ${LOG}
      export cmd="export ORACLE_HOME=${dboraclehome}; export ORACLE_SID=${actioninstancename}; echo -ne 'set head off\n set pagesize 0\n ALTER DATABASE OPEN;' | ${dboraclehome}/bin/sqlplus -s '/ AS SYSDBA'"
      ssh -n ${nodename} ${cmd}  >> ${LOG}

      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Open Database on ${nodename} for ${actiondbname} instance ${actioninstancename} was successful."
         echo "Open Database on ${nodename} for ${actiondbname} instance ${actioninstancename} was successful."  >> ${LOG}
      else
         echo "Open Database on ${nodename} for ${actiondbname} instance ${actioninstancename} was not successful."
         echo "Open Database on ${nodename} for ${actiondbname} instance ${actioninstancename} was not successful."  >> ${LOG}
         exit 8
      fi
 
      fi

   done

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "ORACLE_HOME Patching for node ${nodename} for GI ORACLE_HOME ${gioraclehome} and DB ORACLE_HOME ${dboraclehome} Complete."
   echo "ORACLE_HOME Patching for node ${nodename} for GI ORACLE_HOME ${gioraclehome} and DB ORACLE_HOME ${dboraclehome} Complete." >> ${LOG}
   echo "--" >> ${LOG}
   echo "--" >> ${LOG}
   echo "--"
   echo "--"
   echo "Relocate Services As Needed Here!"
   echo "Relocate Services As Needed Here!" >> ${LOG}
   echo "--" >> ${LOG}
   echo "--" >> ${LOG}
   echo "--"
   echo "--"
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Pausing for Period of time before moving to next node for services settlement and Relocate"
   echo "Pausing for Period of time before moving to next node for services settlement and Relocate" >> ${LOG}

   ###############################################################################################
   # If we want to shift services we could develop automated process to move services here
   # Otherwise services will shift when next instance is shutdown as part of RAC
   ###############################################################################################

   # Since we execute in cluster sets we can assume second node is last node and not long wait needed
   if [ "${first_node}" = "Y" ]; then
      export first_node="N"
  
      # 20 min set is standard for service relocation 10 min and 10min to execute
      sleep 1200
   else
      # Specified to sleep and wait for number of seconds as standard for service relocation
      # For most clusters only 2 nodes so this may not be really needed to be long but
      # enough time to execute service relocation
      sleep 600
   fi
done < "${inputfile}"

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "GI/DB ORACLE_HOME Patching Complete."
echo "GI/DB ORACLE_HOME Patching Complete." >> ${LOG}

################################################################################################
# Once all Nodes are patched Execute the datapatch
################################################################################################
echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "Executing the Post Data Patch Process for environment Patched....."
echo "Executing the Post Data Patch Process for environment Patched....." >> ${LOG}
cat ${datapatchinputfile}
cat ${datapatchinputfile} >> ${LOG}

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}' `
   export instname=`echo ${line}| awk '{print $2}' `
   export racdbname=`echo ${line}| awk '{print $3}' `

   #########################################################################################
   # Set dbhome for instance on node and run datapatch from OPATCH location for instance
   export cmd="/usr/local/bin/dbhome ${instname}"
   export ORACLE_HOME=`ssh -n ${nodename} ${cmd} `

   # Check ORACLE_HOME is set
   if [ $? -eq 0 ]; then
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}"
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}" >> ${LOG}
   else
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process"
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process" >> ${LOG}
      exit 8
   fi

   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # If there is an issue sometimes post patch where the sqlpatch does not have execute permissions
   # so need to fix for datapatch to run
   export cmd="chmod 775 ${ORACLE_HOME}/sqlpatch/sqlpatch"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   ################################################################################################
   # Check if Database Instance is running, it needs to be running and open for process to work.
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n select open_mode from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "READ WRITE" ]
    then
       echo "Database is not Open READ WRITE, can not continue with datapatch, exiting skipping database......"
       echo "Database is not Open READ WRITE, can not continue with datapatch, exiting skipping database......" >> ${LOG}
       #exit 8
   else 
      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Executing the Datapatch for ${instname} on ${nodename}"
      echo "Executing the Datapatch for ${instname} on ${nodename}" >> ${LOG}

      ################################################################################################
      # Execute the datapatch This assumes being done rolling
      echo "Running datapatch for ${instname} on ${nodename}"
      echo "Running datapatch for ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; $ORACLE_HOME/OPatch/datapatch -verbose -skip_upgrade_check"
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
   fi

   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
   ssh -n ${nodename} ${cmd} >> ${LOG}
done < "${datapatchinputfile}"

echo "----------------------------------------------------------------------------------------------"
echo "----------------------------------------------------------------------------------------------" >> ${LOG}
echo "Datapatch for all nodes/instances in list from ${datapatchinpufile} successful."
echo "Datapatch for all nodes/instances in list from ${datapatchinpufile} successful." >> ${LOG}
echo "################################################################################################"
echo "################################################################################################" >> ${LOG}


echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "Qtr DB Patch Update Process Complete!"
echo "Qtr DB Patch Update Process Complete!" >> ${LOG}

exit 0
