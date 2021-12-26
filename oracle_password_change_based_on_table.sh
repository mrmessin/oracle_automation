############################################################################
# dba_change_passwords.sh
#
# Requirements
#		Run from monitor repository database server
#       Parameter needed is dbinstance that contains table to create db list like Example:
#         Example:
#			etlstg2  system   password1
#           etlstg2  avdba    password2
#			avqa1	 system   password3
############################################################################
# create file list from table query put in variable
export dbdriver=$1

dbuserlist = `echo "select dbname || ' ' || username || ' ' || password from <tablename> where xyx = xyz ;" | $ORACLE_HOME/bin/sqlplus /@${dbriver}"`

# Go through each database in cluster check is instance running on node being patched
for line in ${dbuserlist}
do 
   ########################################################
   # Assign the nodename and agent home for processing
   export db=`echo ${line}| awk '{print $1}'`
   export user=`echo ${line}| awk '{print $2}'`
   export password=`echo ${line}| awk '{print $3}'`
   
   # check user exists
   export result = `echo 'select username from dba_users where username = ''${user}\'' ;' | $ORACLE_HOME/bin/sqlplus /@${db}"`

   if [ "${result}" = "" ]
    then
       echo "User ${user} not found in database ${db}"	
   else
      # execute change password
	  echo 'alter user ${user} identified by ${password} ;' | $ORACLE_HOME/bin/sqlplus /@${db}"
   fi
done 

exit 0