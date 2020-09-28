﻿function ConvertTo-DSCObject
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.String]
        $Path,

        [Parameter()]
        [System.String]
        $Content,

        [Parameter()]
        [System.Boolean]
        $IncludeComments = $false
    )

    #region Variables
    $ParsedResults = @()
    #endregion

    # Define components we wish to filter out
    $noisyTypesDesktop = @("NewLine", "StatementSeparator", "Command", "CommandArgument", "CommandParameter")
    $noisyTypesCore = @("NewLine", "StatementSeparator", "CommandArgument", "CommandParameter")
    if (-not $IncludeComments)
    {
        $noisyTypesDesktop += "Comment"
        $noisyTypesCore += "Comment"
    }
    $noisyOperators = (".",",", "")
    
    # Tokenize the file's content to break it down into its various components;
    if (([System.String]::IsNullOrEmpty($Path) -and [System.String]::IsNullOrEmpty($Content)) -or `
        (![System.String]::IsNullOrEmpty($Path) -and ![System.String]::IsNullOrEmpty($Content)))
    {
        throw "You need to specify either Path or Content as parameters."
    }
    elseif (![System.String]::IsNullOrEmpty($Path))
    {
        $parsedData = [System.Management.Automation.PSParser]::Tokenize((Get-Content $Path), [ref]$null)
    }
    elseif (![System.String]::IsNullOrEmpty($Content))
    {
        $parsedData = [System.Management.Automation.PSParser]::Tokenize($Content, [ref]$null)
    }

    [array]$componentsArray = @()
    $currentValues = @()
    $nodeKeyWordEncountered = $false
    $ObjectsToClose = 0
    for ($i = 0; $i -lt $parsedData.Count; $i++)
    {    
        if ($nodeKeyWordEncountered)
        {
            if ($parsedData[$i].Type -eq "GroupStart" -or $parsedData[$i].Content -eq '{')
            {
                $ObjectsToClose++
            }
            elseif (($parsedData[$i].Type -eq "GroupEnd" -or $parsedData[$i].Content -eq '}') -and $ObjectsToClose -gt 0)
            {
                $ObjectsToClose--
            }

            if ($parsedData[$i].Type -notin $noisyTypes -and $parsedData[$i].Content -notin $noisyParts)
            {
                $currentValues += $parsedData[$i]
                if($parsedData[$i].Type -eq "GroupEnd" -and $parsedData[$i].Content -eq '}' -and $ObjectsToClose -eq 0)
                {
                    $componentsArray += ,$currentValues
                    $currentValues = @()
                    $ObjectsToClose = 0
                }
            }
            elseif (($parsedData[$i].Type -eq "GroupEnd" -and $parsedData[$i-2].Content -ne 'parameter' -and $parsedData[$i].Content -ne '}') -or 
                ($parsedData[$i].Type -eq "GroupStart" -and $parsedData[$i-1].Content -ne 'parameter' -and $parsedData[$i].Content -ne '{'))
            {
                $currentValues += $parsedData[$i]
            }
        }
        elseif ($parsedData[$i].Content -eq 'node')
        {
            $nodeKeyWordEncountered = $true
            $newIndexPosition = $i+1
            while ($parsedData[$newIndexPosition].Type -ne 'Keyword')
            {
                $i++
                $newIndexPosition = $i+1
            }
        }
    }

    $ParsedResults = Get-HashtableFromGroup -Groups $componentsArray -Path $Path
    return $ParsedResults
}

function Get-HashtableFromGroup
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Array]
        $Groups,

        [Parameter(Mandatory = $true)]
        [System.Array]
        $Path,

        [Parameter()]
        [System.Boolean]
        $IsSubGroup = $false
    )

    # Loop through all the Resources identified within our configuration
    $currentIndex = 1
    $result = @()
    $ParsedResults = @()
    foreach ($group in $Groups)
    {
        $keywordFound = $false
        if (-not $IsSubGroup -and $currentIndex -le $Groups.Count-2)
        {
            Write-Progress -PercentComplete ($currentIndex / ($Groups.Count-2) * 100) -Activity "Parsing $Path [$($currentIndex)/$($Groups.Count-2)]"
        }
        $currentPropertyIndex = 0
        $currentProperty = ''
        while ($currentPropertyIndex -lt $group.Count)
        {
            $component = $group[$currentPropertyIndex]
            if ($component.Type -eq "Keyword" -and -not $keywordFound)
            {
                $result = @{ ResourceName = $component.Content }
                $keywordFound = $true
            }
            elseif ($keywordFound)
            {
                # If the next component is a keyword and we've already identified a keyword for this group, that means that we are
                # looking at a CIMInstance property;
                if ($component.Type -eq "Keyword")
                {
                    $currentGroupEndFound = $false
                    $currentPosition = $currentPropertyIndex + 1
                    $subGroup = @($component)
                    $ObjectsToClose = 0
                    $allSubGroups = @()
                    [Array]$subResult = @()
                    while (!$currentGroupEndFound)
                    {
                        $currentSubComponent = $group[$currentPosition]
                        if ($currentSubComponent.Type -eq 'GroupStart' -or $currentSubComponent.Content -eq '{')
                        {
                            $ObjectsToClose++
                        }
                        elseif ($currentSubComponent.Type -eq 'GroupEnd' -or $currentSubComponent.Content -eq '}')
                        {
                            $ObjectsToClose--
                        }

                        $subGroup += $group[$currentPosition]
                        if ($ObjectsToClose -eq 0 -and $group[$currentPosition+1].Type -ne 'Keyword' -and `
                            $group[$currentPosition].Type -ne 'Keyword')
                        {
                            $currentGroupEndFound = $true
                        }
                        
                        if ($ObjectsToClose -eq 0 -and $group[$currentPosition].Type -ne 'Keyword')
                        {
                            $allSubGroups += ,$subGroup
                            $subGroup = @()
                        }
                        $currentPosition++
                    }
                    $currentPropertyIndex = $currentPosition
                    $subResult = Get-HashtableFromGroup -Groups $allSubGroups -IsSubGroup $true -Path $Path
                    $allSubGroups = @()
                    $subGroup = @()
                    $result.$currentProperty = $subResult
                }
                # If the next component is not an operator, that means that the current member is part of the previous property's
                # value;
                elseif ($group[$currentPropertyIndex + 1].Type -ne "Operator" -and $component.Content -ne "=" -and `
                        $component.Content -ne '{' -and $component.Content -ne '}' -and $group[$currentPropertyIndex + 1].Type -ne 'Keyword')
                {
                    switch ($component.Type)
                    {
                        {$_ -in @("String","Number")} {
                            $result.$currentProperty += $component.Content
                        }
                        {$_ -in @("Variable")} {
                            $result.$currentProperty += "`$" + $component.Content
                        }
                        {$_ -in @("Member")} {
                            $result.$currentProperty += "." + $component.Content
                        }
                        {$_ -in @("Comment")} {
                            $result.$("_metadata_" + $currentProperty) += $component.Content
                        }
                        {$_ -in @("GroupStart")} {
                            $result.$currentProperty += "@("

                            do
                            {
                                if ($group[$currentPropertyIndex].Content -notin @("@(", ")"))
                                {
                                    $result.$currentProperty += "`"" + $group[$currentPropertyIndex].Content + "`",`""
                                }
                                $currentPropertyIndex++
                            }
                            while ($group[$currentPropertyIndex].Type -ne 'GroupEnd')

                            if (($result.$currentProperty).EndsWith(","))
                            {
                                $result.$currentProperty = ($result.$CurrentProperty).Substring(0, ($result.$CurrentProperty).Length -1) + ")"
                            }
                            else
                            {
                                $result.$currentProperty += ')'
                            }
                        }
                    }
                }
                elseif ($component.Content -notin $noisyOperators)
                {
                    switch ($component.Type)
                    {
                        "Member" {
                            $currentProperty = $component.Content.ToString()

                            if(!$result.Contains($currentProperty))
                            {
                                $result.Add($currentProperty, $null)
                            }
                        }
                    }
                }
            }
            $currentPropertyIndex++
        }

        if($keywordFound)
        {
            $ParsedResults += $result
        }
        $currentIndex++
    }
    return $ParsedResults
}

function Get-VariableListFromDSC
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $parsedData = [System.Management.Automation.PSParser]::Tokenize((Get-Content $Path), [ref]$null)
    $results = @{}
    for ($i = 0; $i -le $parsedData.Count; $i++)
    {
        if ($parsedData[$i].Type -eq "Variable")
        {
            $variableName = $parsedData[$i].Content
            if ($parsedData[$i+1].Type -eq 'Operator' -and $parsedData[$i+1].Content -eq '=')
            {
                if ($parsedData[$i+2].Type -in @("Command", "Variable"))
                {
                    $variableValue = ""

                    $currentIndex = 2
                    do
                    {
                        if ($parsedData[$i+$currentIndex].Type -eq 'CommandParameter')
                        {
                            $variableValue += " " + $parsedData[$i+$currentIndex].Content
                        }
                        elseif ($parsedData[$i+$currentIndex].Type -eq 'String')
                        {
                            if ($parsedData[$i+$currentIndex-1].Type -ne 'GroupStart')
                            {
                                $variableValue += ' '
                            }
                            $variableValue += "`"" + $parsedData[$i+$currentIndex].Content + "`""
                        }
                        elseif ($parsedData[$i+$currentIndex].Type -eq 'Variable')
                        {
                            $variableValue += "`$" + $parsedData[$i+$currentIndex].Content
                        }
                        else
                        {
                            $variableValue += $parsedData[$i+$currentIndex].Content
                        }
                        $currentIndex++
                    }
                    while ($parsedData[$i+$currentIndex].Type -ne 'Newline')
                    $variableValue = [ScriptBlock]::Create($variableValue)
                }
                else
                {
                    $variableValue = $parsedData[$i+2].Content
                }

                if (-not $results.Contains($variableName))
                {
                    $results.Add($variableName, $variableValue)
                }
            }
        }
    }
    return $results
}
