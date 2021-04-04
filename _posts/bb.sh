#!/bin/sh
#****************************************************************#
# ScriptName: aa.sh
# Author: $SHTERM_REAL_USER@alibaba-inc.com
# Create Date: 2019-01-31 14:02
# Modify Author: @alibaba-inc.com
# Modify Date: 2021-04-04 17:50
# Function: 
#***************************************************************#

for i in `ls  *.md`; do 
	head -n 20 $i | grep categories;
	if [[ $? == 0 ]];then
		continue
	fi

	echo "######################3"
	data=`head -n 10 $i | grep tags -A 3`
	

	echo "$data" | grep "memory"
	if [[ $? == 0 ]];then
		TEXT="categories:memory"; 
	else
		TEXT=""
	fi

	if [[ -n $TEXT ]];then
		echo "====$i == $TEXT"
		sed -i "/author:/a\\$TEXT" $i
	fi
done
