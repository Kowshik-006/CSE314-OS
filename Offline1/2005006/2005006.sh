#!/usr/bin/bash

# Checking if the provided option is valid
if [ $1 != "-i" ]; then
    echo "Invalid option $1" >&2; 
    exit 1
fi

# The second argument is the input file
inputFile=$2

# Checking if the input file exists
# -f checks if the file exists and is a regular file
if [ ! -f "$inputFile" ]; then
    echo "Input file not found!"
    exit 1
fi

# Read the input file
# 'np' -> nth line
archiveOn=$(sed -n '1p' "$inputFile" | tr -d '\r'| xargs)  
validArchiveTypes=$(sed -n '2p' "$inputFile" | tr -d '\r' | xargs)   
allowedLanguages=$(sed -n '3p' "$inputFile" | tr -d '\r' | xargs) 
totalMarks=$(sed -n '4p' "$inputFile" | tr -d '\r' | xargs)  
mismatchPenalty=$(sed -n '5p' "$inputFile" | tr -d '\r' | xargs)  
workingDirectory=$(sed -n '6p' "$inputFile" | tr -d '\r')  
rollRange=$(sed -n '7p' "$inputFile" | tr -d '\r' | xargs) 
expectedOutput=$(sed -n '8p' "$inputFile" | tr -d '\r' | xargs)  
subViolationPenalty=$(sed -n '9p' "$inputFile" | tr -d '\r' | xargs)  
plagFile=$(sed -n '10p' "$inputFile" | tr -d '\r' | xargs)  
plagPenalty=$(sed -n '11p' "$inputFile" | tr -d '\r' | xargs)  

firstRoll=$(echo "$rollRange" | cut -d' ' -f1)  
lastRoll=$(echo "$rollRange" | cut -d' ' -f2)  

expectedOutputFileName=$(basename "$expectedOutput")
plagFileName=$(basename "$plagFile")

echo "Plagiarism file: $plagFile"
echo $(cat "$plagFile")


if ! [[ $firstRoll =~ ^[0-9]+$ ]] || ! [[ $lastRoll =~ ^[0-9]+$ ]]; then
    echo $firstRoll
    echo $lastRoll
    echo "Not numbers"
    exit 1
fi

echo "id,marks,marks_deducted,total_marks,remarks" > marks.csv


if [ ! -d "$workingDirectory/issues" ]; then
    mkdir -p "$workingDirectory/issues" 
fi

if [ ! -d "$workingDirectory/checked" ]; then
    mkdir -p "$workingDirectory/checked"
fi


# Student submissions are in the working directory
for file in "$workingDirectory"/*; do
    foundIssues="false"
    if  [ "$file" == "$expectedOutputFileName" ] || [ "$file" == "$plagFileName" ]; then
        continue
    fi
    # basename extracts the file name from the path
    # cut splits the string
    # -d. specifies the delimiter as "."
    # -f1 specifies the 1st substring, the filename
    studentID=$(basename "$file" | tr -d '\r' | cut -d. -f1) 

    deduction=0
    remarks=""
    
    if [[ "$studentID" -lt "$firstRoll"  ||  "$studentID" -gt "$lastRoll" ]]; then
        # skip files with roll numbers outside the range
        continue
    fi

    if [[ "$archiveOn" == "true" ]]; then 
        # Case 1 : Submission is a directory when archive is on
        if [[ -d "$file" ]]; then
            # echo "$file is a directory"
            deduction=$(($deduction + $subViolationPenalty))
            remarks+="issue case #1 "
            foundIssues="true"
        else
            # -f2 specifies the 2nd substring, the extension
            extension=$(basename "$file" | cut -d. -f2) 
            # * checks whether the extension is in the list of valid archive types
            found="false"
            for type in $validArchiveTypes; do
                if [ "$type" == "$extension" ]; then
                    found="true"
                    break
                fi
            done
            # Case 2 : Unsupported archive format
            if [ "$found" == "false" ]; then
                # echo "Skipping $file: Unsupported archive format"
                remarks+="issue case #2 "
                deduction=$(($deduction + $subViolationPenalty))
                total=$((0 - $deduction))
                echo "$studentID,0,$deduction,$total,$remarks" >> marks.csv
                foundIssues="true"

                continue
            fi

            # Unarchive the file and put the contents in a directory with the student's ID
            if [ ! -d "$workingDirectory/$studentID" ]; then
                mkdir -p "$workingDirectory/$studentID"
            fi
            if [[ "$extension" == "zip" ]]; then
                unzip "$file" -d "$workingDirectory/$studentID"  
            elif [[ "$extension" == "tar" ]]; then
                tar -xvf "$file" -C "$workingDirectory/$studentID"  
            fi

            echo "Extracted the archived file"

            for content in "$workingDirectory/$studentID"/*; do
                # Case 4 : Extracted folder name doesn't match the student ID
                folder_name=$(basename "$content")
                if [[ "$folder_name" != "$studentID" ]]; then
                    deduction=$(($deduction + $subViolationPenalty))
                    remarks+="issue case #4 "
                    foundIssues="true"
                fi
            done
            for content in "$workingDirectory/$studentID"/*; do
                for file in "$content"/*; do
                    mv "$file" "$workingDirectory/$studentID"
                done
                rm -rf "$content"
            done
            echo "Moved the contents of the extracted folder to its parent"
        fi

    else
        # If the submission isn't archived, move it to a directory for the student
        # KAJ BAKI ASE!!!
        if [ ! -d "$workingDirectory/$studentID" ]; then
            mkdir -p "$workingDirectory/$studentID"
        fi
        mv "$file" "$workingDirectory/$studentID"
    fi

    # Checking if the file is in an allowed language
    submissionFile=$(find "$workingDirectory/$studentID" -type f)  
    fileExtension="$(echo "$submissionFile" | cut -d. -f2)"  
    submissionDirectory="$workingDirectory/$studentID"

    found="false"

    for language in $allowedLanguages; do
        if [ "$language" == "python" ]; then
            language="py"
        fi  
        if [ "$language" == "$fileExtension" ]; then
            found="true"
            break
        fi
    done
    # Case 3 : Unsupported language
    if [ "$found" == "false" ]; then
        echo "Skipping $file: Unsupported language"
        deduction=$(($deduction + $subViolationPenalty))
        remarks+="issue case #3 "
        total=$((0 - $deduction))
        echo "$studentID,0,$deduction,$total,$remarks" >> marks.csv
        foundIssues="true"
        mv "$workingDirectory/$studentID" "$workingDirectory/issues"
        continue
    fi

    # Run the submission based on its language
    case "$fileExtension" in
        "c") gcc "$submissionFile" -o "$submissionDirectory/${studentID}.out" && "$submissionDirectory/${studentID}.out" > "$submissionDirectory/${studentID}_output.txt" ;;  
        "cpp") g++ "$submissionFile" -o "$submissionDirectory/${studentID}.out" && "$submissionDirectory/${studentID}.out" > "$submissionDirectory/${studentID}_output.txt" ;; 
        "py") python3 "$submissionFile" > "$submissionDirectory/${studentID}_output.txt" ;;  
        "sh") bash "$submissionFile" > "$submissionDirectory/${studentID}_output.txt" ;;  
    esac

    # -w ignores all white spaces
    # -B ignores blank lines
    # wc -l counts the number of lines
    # > indicates the lines that are present in the second file but not in the first file
    mismatchCount=$(diff -w -B "$submissionDirectory/${studentID}_output.txt" "$expectedOutput" | grep "^>" | wc -l) 

    mismatchDeduction=0
    if [ $mismatchCount -gt 0 ]; then
        mismatchDeduction=$(($mismatchPenalty * $mismatchCount))
    fi

    echo >> "$plagFile" # Add a new line to the end of the file

    plagiarised="false"
    echo $(cat "$plagFile")
    while read -r word; do
        echo "Reading from plagiarism.txt"
        word=$(echo "$word" | tr -d '\r' | xargs)
        echo "Read from $plagFileName: $word"
        if [ "$word" == "$studentID" ]; then
            echo "Match found: $word"
            plagiarised="true"
            break
        fi
    done < "$plagFile" # Convert spaces to new lines

    marks=$(($totalMarks - $mismatchDeduction))
    totMarks=$(($marks - $deduction))

    if [ "$plagiarised" == "true" ]; then
        remarks+="plagiarism detected "
        echo "$studentID,$marks,$deduction,-100,$remarks" >> marks.csv
    else    
        echo "$studentID,$marks,$deduction,$totMarks,$remarks" >> marks.csv
    fi

    if [ "$foundIssues" == "true" ]; then
        mv "$workingDirectory/$studentID" "$workingDirectory/issues"
    else
        mv "$workingDirectory/$studentID" "$workingDirectory/checked"
    
    fi

done
