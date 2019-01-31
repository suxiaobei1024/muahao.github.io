#!/bin/sh
#****************************************************************#
# ScriptName: aa.sh
# Author: $SHTERM_REAL_USER@alibaba-inc.com
# Create Date: 2019-01-31 14:02
# Modify Author: $SHTERM_REAL_USER@alibaba-inc.com
# Modify Date: 2019-01-31 14:02
# Function: 
#***************************************************************#

for i in `ls  *.md`; do 
	CONTENT=`cat $i | grep title | awk -F":" '{print $2}' | tr -d "\""`; 
	TEXT="excerpt:$CONTENT"; 
	sed -i "/author:/a\\$TEXT" $i
done
