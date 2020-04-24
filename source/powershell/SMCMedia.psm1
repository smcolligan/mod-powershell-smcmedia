function Get-GooglePhotosLocalSource() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>

  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$true)]
      [string]$SourceDefinitionPath='\\nas2\scripts\data\google-photos-local-sources.json'
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # import google-photos type sources json
    $sources = Get-Content -Path $SourceDefinitionPath | ConvertFrom-Json | Where-Object {$_.sources.type -eq 'google-photos'} | Select-Object -ExpandProperty 'sources'

    # loop through each source
    foreach ($source in $sources) {

      # create source object
      $sourceObject = [pscustomobject]@{
        Name = $source.name
        Path = $source.path
      }

      # return object
      Write-Output $sourceObject
    }
  }
}
function New-FileAuditRecord() {

  <#
    .SYNOPSIS
    Audits a file and produces an audit record containing the hash, size, and last write date/time of the file

    .EXAMPLE
    New-FileAuditRecord
    # generate an audit record
  #>
  [CmdletBinding(SupportsShouldProcess=$true)]

  param (
    [Alias("FullName")]
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string[]]$Path,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$AuditName,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$HashAlgorithm='SHA512'
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {

    # loop through each item in pipeline and/or array
    foreach ($pathItem in $Path) {

      # make sure the path is valid and points to a file
      if (Test-Path -Path $pathItem -PathType Leaf) {

        Write-Verbose ('Generating audit record for file "{0}"' -f $pathItem)

        # start timer
        $timer = [Diagnostics.Stopwatch]::StartNew()

        # get reference to file object
        $fileItem = Get-Item -Path $pathItem

        # generate file hash
        $fileHash = Get-FileHash -Path $pathItem -Algorithm $HashAlgorithm

        # create custom object to store file audit record
        $fileAuditRecord = [PSCustomObject]@{
          AuditName = $AuditName
          AuditDateTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
          AuditElapsedSeconds = $timer.Elapsed.Seconds
          Path = [System.IO.Path]::GetDirectoryName($pathItem)
          FileName = [System.IO.Path]::GetFileNameWithoutExtension($pathItem)
          FileExtension = [System.IO.Path]::GetExtension($pathItem)
          FileLength = $fileItem.Length
          FileLastWriteDateTime = Get-Date($fileItem.LastWriteTime) -Format 'yyyy-MM-dd HH:mm:ss'
          HashAlgorithm = $fileHash.Algorithm
          HashValue = $fileHash.Hash
        }

        # return file audit record
        Write-Output $fileAuditRecord
      }
      else {
        Write-Error ('Unable to access file at path "{0}".' -f $pathItem)
      }
    }
  }

  end {}
}
function Import-GooglePhotosCatalog() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$Path='\\nas2\scripts\catalogs\google-photos-catalog.csv'
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # import the csv catalog and return
    Import-Csv -Path $Path
  }
}
function Find-CatalogItem() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [psobject]$Catalog,
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$HashValue
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # search catalog for item with matching hash value and return
    $Catalog | Where-Object {$_.HashValue -eq $HashValue}
  }
}
function Add-GooglePhotosCatalogItem() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$Path='\\nas2\scripts\catalogs\google-photos-catalog.csv',
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [ref]$Catalog,
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [psobject]$AuditRecord
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    Write-Verbose ('Adding item with hash value "{0}" and name "{1}" to catalog.' -f $AuditRecord.HashValue, $AuditRecord.FileName)

    # add file audit to catalog, handling single items for inital conditions
    if ($Catalog.value -is [System.Array]) {
      $Catalog.value += $AuditRecord
    }
    else {
      $Catalog.value = @($Catalog.value, $AuditRecord)
    }

    # export catalog to file, appending new record
    $AuditRecord | Export-Csv -Path $Path -Append -NoTypeInformation
  }
}
function Import-GooglePhotosItem() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Photos,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Videos
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $mediaExtensions = @()
    $catalog = @()

    # include photo extensions if specified
    if ($Photos) {
      $mediaExtensions += Get-PhotoFileExtensions
    }

    # include video extensions if specified
    if ($Videos) {
      $mediaExtensions += Get-VideoFileExtensions
    }

    # if neither photos/videos were specifed, load both
    if ($mediaExtensions.Length -eq 0) {
      $mediaExtensions = Get-MediaFileExtensions
    }

    # load catalog
    $catalog = Import-GooglePhotosCatalog

    # load sources
    $sources = Get-GooglePhotosLocalSources
  }

  process {}

  end {

    # load file list, filtering by media extension
    $files = $sources | Get-ChildItem  | Where-Object {$_.Extension -in $mediaExtensions}

    # loop through files
    foreach ($file in $files) {

      # generate an audit record
      $auditRecord = $file | New-FileAuditRecord

      # search catalog for record
      if (!(Find-CatalogItem -Catalog $catalog -HashValue $auditRecord.HashValue)) {
        Write-Verbose ('Item with hash value "{0}" and name "{1}" was NOT found in catalog.' -f $auditRecord.HashValue, $auditRecord.FileName)

        # # import file
        # Import-SMCMedia -Path $file.FullName -SkipBackup

        # add record to catalog
        Add-GooglePhotosCatalogItem -Catalog ([ref]$catalog) -AuditRecord $auditRecord
      }
    }
  }
}
function Get-MediaFileExtension() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>

  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$PhotoRaw,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$PhotoDev,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Video,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$IncludePhotoDataFiles
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $fileExtensions = @()

    # init photo file extensions
    $photoDevFileExtensions = @()
    $photoDevFileExtensions += '.jpg'
    $photoDevFileExtensions += '.jpeg'

    # init photo raw file extensions
    $photoRawFileExtensions = @()
    $photoRawFileExtensions += '.cr2'
    $photoRawFileExtensions += '.arw'
    $photoRawFileExtensions += '.tif'
    $photoRawFileExtensions += '.tiff'
    $photoRawFileExtensions += '.dng'

    # init photo data file extensions
    $photoDataFileExtensions = @()
    $photoDataFileExtensions += '.xmp'

    # init video file extensions
    $videoFileExtensions = @()
    $videoFileExtensions += '.mp4'
    $videoFileExtensions += '.mts'
    $videoFileExtensions += '.avi'
    $videoFileExtensions += '.mov'
  }

  process {}

  end {

    # if no switches present, return all extensions
    if ((!$PhotoRaw) -and (!$PhotoDev) -and (!$Video)) {
      $fileExtensions += $photoRawFileExtensions
      $fileExtensions += $photoDevFileExtensions
      $fileExtensions += $videoFileExtensions
    }
    else {

      # if photoraw switch present, add extensions
      if ($PhotoRaw) {
        $fileExtensions += $photoRawFileExtensions
      }

      # if photoraw switch present, add extensions
      if ($PhotoDev) {
        $fileExtensions += $photoDevFileExtensions
      }

      # if photodata switch present, add extensions
      if ($PhotoData) {
        $fileExtensions += $photoDataFileExtensions
      }

      # if video switch present, add extensions
      if ($Video) {
        $fileExtensions += $videoFileExtensions
      }
    }

    if ($IncludePhotoDataFiles) {
      $fileExtensions += $photoDataFileExtensions
    }

    # return object
    Write-Output $fileExtensions
  }
}
function Get-MediaFileType() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>

  [OutputType([string])]
  [CmdletBinding()]

  param (
    [Alias('FullName')]
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string[]]$MediaFilePath
  )

  begin {
    $ErrorActionPreference = "Stop"

    # get photo file extensions
    $photoFileExtensions = Get-MediaFileExtension -PhotoRaw
    $photoFileExtensions += Get-MediaFileExtension -PhotoDev

    # get video file extensions
    $videoFileExtensions = Get-MediaFileExtension -Video
  }

  process {

    # loop through each item
    foreach ($item in $MediaFilePath) {

      # get extension of current item
      $extension = [System.IO.Path]::GetExtension($item)

      # use extension to determine media type
      if ($extension -in $photoFileExtensions) {
        return "photo"
      }
      elseif ($extension -in $videoFileExtensions) {
        return "video"
      }
      else {
        Write-Error ('Unknown media file type for file {0}' -f $item)
      }
    }
  }

  end {

    # get item reference
    $item = Get-Item -Path $MediaFilePath

  }
}
function Get-MediaFile() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>

  [CmdletBinding()]

  param (
    [Alias('FullName')]
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string[]]$Path,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Recurse,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$PhotoRaw,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$PhotoDev,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Video,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$IncludePhotoDataFiles
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init getmediafileextension param hashtable
    $paramGetMediaFileExtension = @{}

    if ($PhotoRaw) {
      $paramGetMediaFileExtension.PhotoRaw = $true
    }

    if ($PhotoDev) {
      $paramGetMediaFileExtension.PhotoDev = $true
    }

    if ($IncludePhotoDataFiles) {
      $paramGetMediaFileExtension.IncludePhotoDataFiles = $true
    }

    if ($Video) {
      $paramGetMediaFileExtension.Video = $true
    }

    # get media file extensions
    $fileExtensions = Get-MediaFileExtension @paramGetMediaFileExtension

    # init getchilditem param hash table
    $paramGetChildItem = @{}
    $paramGetChildItem.File = $true

    # if recurse switch present, add it to param hashtable
    if ($Recurse) {
      $paramGetChildItem.Recurse = $true
    }
  }

  process {

    # loop through each item in array
    foreach ($item in $Path) {

      # add path property and value to param hashtable for this item
      $paramGetChildItem.Path = $item

      # get child items for given path that match selected extensions
      Get-ChildItem @paramGetChildItem | Where-Object {$_.Extension -in $fileExtensions}
    }
  }

  end {
  }
}
function Get-MediaFileExifRecord() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Alias('FullName')]
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string[]]$MediaFilePath
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $mediaFilePaths = @()

    <#
      To enable large file support, you need to have the following config:

        %Image::ExifTool::UserDefined::Options = (
          LargeFileSupport => 1,
        );

      ...defined in your .ExifTool_config file located in your home directory

      I tried adding command line arguments to do this, but while it works from the command line, it doesn't work from an arg file
    #>

    # create array of commands to control execution of exiftool
    $commands = @()
    $commands += '-s' # prints tag names in the output instead of descriptions

    # create array of tags to read from media files
    $tagNames = @()

    # tags that help identify which date/time field to read
    $tagNames += '-ComAndroidManufacturer'
    $tagNames += '-ComAndroidModel'
    $tagNames += '-Make'
    $tagNames += '-Model'
    $tagNames += '-UsePanoramaViewer'
    $tagNames += '-DeviceManufacturer'
    $tagNames += '-DeviceModelName'

    # tags that contain date/time values
    $tagNames += '-DateTimeOriginal'
    $tagNames += '-MediaCreateDate'
    $tagNames += '-ModifyDate'
    $tagNames += '-LastPhotoDate'
    $tagNames += '-CreationDateValue'
    $tagNames += '-FileName'
  }

  process {

    # loop through each media file path and add to array
    foreach($item in $MediaFilePath) {
      $mediaFilePaths += $item
    }
  }

  end {

    # cache current whatif preference
    $currentWhatIfPreference = $WhatIfPreference

    # turn off whatif preference
    $WhatIfPreference = $false

    # create new arg file
    $argFilePath = New-ExifToolArgFile -Command ($commands + $tagNames) -MediaFilePath $mediaFilePaths
    
    # invoke exif tool
    $results = Invoke-ExifTool -Arguments ('-@', $argFilePath)

    # if exif tool invocation was successful
    if ($results.Success) {

      # create params hash for call to ConvertFrom-ExifToolOutput
      $convertOutputParams = @{}
      $convertOutputParams.Output = $results.Output
      $convertOutputParams.TagNames = $tagNames
      if (($mediaFilePaths | Measure-Object).Count -eq 1) {
        $convertOutputParams.SingleFilePath = $mediaFilePaths[0]
      }

      # convert output to powershell object(s)
      ConvertFrom-ExifToolOutput @convertOutputParams
    }
    else {
      Write-Error $results.Output
    }

    # remove arg file
    Remove-ExifToolArgFile -Path $argFilePath

    # restore whatif preference
    $WhatIfPreference = $currentWhatIfPreference
  }
}
function Get-MediaFileDateTimeRecord() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$false)]
      [psobject]$MediaFileExifRecord,
    [ValidateSet('photo','video')]
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$MediaFileType
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init return object
    $dateTimeRecord = [pscustomobject]@{
      Name = $null
      Value = $null
    }

    # if media file type was passed, use it - otherwise look it up
    if ($MediaFileType) {
      $workingMediaFileType = $MediaFileType
    }
    else {
      $workingMediaFileType = Get-MediaFileType -MediaFilePath $MediaFileExifRecord.MediaFilePath
    }

  }

  process {

    # init return object
    $dateTimeRecord.Name = $null
    $dateTimeRecord.Value = $null

    # handle each media file type
    switch ($workingMediaFileType) {
      'photo' {

        # if DateTimeOriginal exists, use it
        if ($MediaFileExifRecord.DateTimeOriginal) {
          $dateTimeRecord.Name = 'DateTimeOriginal'
          $dateTimeRecord.Value = $MediaFileExifRecord.DateTimeOriginal
        }
        elseif ($MediaFileExifRecord.ModifyDate) {
          $dateTimeRecord.Name = 'ModifyDate'
          $dateTimeRecord.Value = $MediaFileExifRecord.ModifyDate
        }
        else {
          Write-Error ('Not Implemented for photo file {0}' -f $MediaFileExifRecord.MediaFilePath)
        }
      }
      'video' {

        Write-Verbose ('DeviceManufacturer = {0}' -f $MediaFileExifRecord.DeviceManufacturer)
        Write-Verbose ('DeviceModelName = {0}' -f $MediaFileExifRecord.DeviceModelName)
        Write-Verbose ('CreationDateValue = {0}' -f $MediaFileExifRecord.CreationDateValue)

        # video from sony a6300
        if (($MediaFileExifRecord.DeviceManufacturer -eq 'Sony') -and ($MediaFileExifRecord.DeviceModelName -eq 'ILCE-6300') -and ($MediaFileExifRecord.CreationDateValue)) {
          $dateTimeRecord.Name = 'CreationDateValue'
          $dateTimeRecord.Value = ($MediaFileExifRecord.CreationDateValue -replace '-.*')
        }
        elseif (($MediaFileExifRecord.ComAndroidManufacturer -eq 'motorola') -and ($MediaFileExifRecord.ComAndroidModel -eq 'moto x4') -and ($MediaFileExifRecord.FileName)) {
          $dateTimeRecord.Name = 'FileName'
          $dateTimeRecord.Value = ($MediaFileExifRecord.FileName -replace 'VID_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(\d{3}).mp4', '$1:$2:$3 $4:$5:$6')
        }
        else {

          # if MediaCreateDate exists, use it
          if ($MediaFileExifRecord.MediaCreateDate) {
            $dateTimeRecord.Name = 'MediaCreateDate'
            $dateTimeRecord.Value = $MediaFileExifRecord.MediaCreateDate
          }
          else {
            Write-Error ('Not Implemented for video file {0}' -f $MediaFileExifRecord.MediaFilePath)
          }
        }
      }
    }

    # if record has a name value, return it
    if ($dateTimeRecord.Name) {
      Write-Output $dateTimeRecord
    }
  }

  end {
  }
}
function Get-MediaFileRecord() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Alias('FullName')]
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string[]]$MediaFilePath
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $mediaFilePaths = @()
    $mediaFileRecords = @()
  }

  process {

    # loop through each media file path and add to array
    foreach($item in $MediaFilePath) {
      $mediaFilePaths += $item
    }
  }

  end {

    # get date time values for each media file
    $mediaFileExifRecords = Get-MediaFileExifRecord -MediaFilePath $mediaFilePaths

    # loop through each path
    foreach ($item in $mediaFilePaths) {

      # get corresponding date/time object
      $mediaFileExifRecord = $mediaFileExifRecords | Where-Object {$_.MediaFilePath -eq $item}

      # get media file type
      $mediaFileType = Get-MediaFileType -MediaFilePath $item

      # get media date time value
      $mediaFileDateTimeRecord = Get-MediaFileDateTimeRecord -MediaFileExifRecord $mediaFileExifRecord -MediaFileType $mediaFileType

      # cast value to datetime
      $workingDateTimeValue = [datetime]::ParseExact($mediaFileDateTimeRecord.Value, 'yyyy:MM:dd HH:mm:ss', $null)

      # create new output object
      $mediaFileRecord = [pscustomobject]@{
        FullName = $item
        Path = [System.IO.Path]::GetDirectoryName($item)
        FileName = [System.IO.Path]::GetFileNameWithoutExtension($item)
        FileExtension = [System.IO.Path]::GetExtension($item)
        FileNameSeriesIndex = 0
        Type = $mediaFileType
        Length = (Get-Item -Path $item | Select-Object -ExpandProperty 'Length')
        DateTimeProperty = $mediaFileDateTimeRecord.Name
        DateTimeValue = $workingDateTimeValue
        TimeStampValue = ('{0}_0000' -f $workingDateTimeValue.ToString('yyyy-MM-dd_HH-mm-ss'))
        ExifRecord = $mediaFileExifRecord
      }

      # add record to array
      $mediaFileRecords += $mediaFileRecord
    }

    # group records on time stamp file name
    $fileNameGroups = $mediaFileRecords | Group-Object -Property 'TimeStampValue' | Where-Object {$_.Count -gt 1}

    # loop through each group
    foreach ($group in $fileNameGroups) {

      # expand the group into its records and sort by original file name
      $records = $group | Select-Object -ExpandProperty 'Group' | Sort-Object -Property 'FileName'

      # initialize index
      $workingIndex = 0

      # loop through each record
      foreach ($record in $records) {

        # set the record file series index
        $record.FileNameSeriesIndex = $workingIndex

        # update time stamp file name
        $record.TimeStampValue = $record.TimeStampValue -replace '0000$', $record.FileNameSeriesIndex.ToString('0000')

        # increment the working index
        $workingIndex += 1
      }
    }

    # output records
    Write-Output $mediaFileRecords
  }
}
function New-ExifToolArgFile() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>

  [OutputType([string])]

  [CmdletBinding(SupportsShouldProcess=$true)]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string[]]$Command,
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string[]]$MediaFilePath
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # combine the commands and paths into a single array
    $lines = @($Command, $MediaFilePath)

    # create a temp file
    $filePath = [System.IO.Path]::GetTempFileName()

    # write lines to temp file
    $lines | Out-File -FilePath $filePath -Encoding utf8

    # return file path
    return $filePath
  }
}
function Remove-ExifToolArgFile() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>

  [CmdletBinding(SupportsShouldProcess=$true)]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$Path
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # remove the arg file
    Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
  }
}
function Invoke-ExifTool() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string[]]$Arguments
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # create custom object to store file audit record
    $invocationResults = [PSCustomObject]@{
      Arguments = $Arguments
      Output = $null
      ExitCode = $null
      Success = $false
    }

    # execute exiftool with arguments and capture stdout & stderr
    try {
      $results = exiftool.exe $Arguments 2>&1
      $invocationResults.ExitCode = $LASTEXITCODE
      $invocationResults.Output = $results
    }
    catch {
      $invocationResults.ExitCode = $LASTEXITCODE
      $invocationResults.Output = $_.Exception.ToString()
    }

    # set success flag
    $invocationResults.Success = ($invocationResults.ExitCode -eq 0)

    # return results
    return $invocationResults
  }
}
function ConvertFrom-ExifToolOutput() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string[]]$Output,
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string[]]$TagNames,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$SingleFilePath
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $currentObject = $null
    $objects = @()
    $properties = [ordered]@{}
    $properties.Add('MediaFilePath', $null)

    # remove leading hyphens from tag names
    $cleanTagNames = $TagNames -replace '-'

    # loop through each item in tag name array and add to hash table
    foreach ($item in $cleanTagNames) {
      $properties.Add($item, $null)
    }
  }

  process {}

  end {

    # join tag names into regex or string
    $regexTagNameString = $cleanTagNames -join '|'

    # create regex string to match tag names
    $regexString = '(' + $regexTagNameString + ')(\s{0,}:\s{0,})(.*)'

    # a single file produces different output in exif tool, specifically no header is output that contains the file name
    if ($SingleFilePath) {

      # create a new object
      $currentObject = New-Object -TypeName 'psobject' -Property $properties

      # set media file path
      $currentObject.MediaFilePath = $SingleFilePath

      # loop through each line in output
      foreach ($line in $Output) {

        # try to match on tag name
        $match = [regex]::Match($line, $regexString)

        # if matched
        if ($match.Success) {

          # set property value on current object
          $currentObject.PSObject.Properties[($match.Groups[1].Value)].Value = $match.Groups[3].Value
        }
      }
    }
    else {

      # loop through each line in output
      foreach ($line in $Output) {

        # if the line matches the start of output for a file
        if ($line -match '={8}\s') {

          # add previous current object to array
          if ($currentObject) {
            $objects += $currentObject
          }

          # create a new object
          $currentObject = New-Object -TypeName 'psobject' -Property $properties

          # set media file path
          $currentObject.MediaFilePath = $line -replace '(={8}\s)(.*)', '$2' -replace '/', '\'
        }
        else {

          # try to match on tag name
          $match = [regex]::Match($line, $regexString)

          # if matched
          if ($match.Success) {

            # set property value on current object
            $currentObject.PSObject.Properties[($match.Groups[1].Value)].Value = $match.Groups[3].Value
          }
        }
      }
    }

    # add current object to array
    if ($currentObject) {
      $objects += $currentObject
    }

    # write objects to pipeline
    Write-Output $objects
  }
}
function Rename-MediaFileWithTimeStamp() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [psobject[]]$MediaFileRecord
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {

    # loop through each item in array
    foreach ($item in $MediaFileRecord) {

      # rename item with timestamp file name
      Rename-Item -Path $item.FullName -NewName ('{0}{1}' -f $item.TimeStampValue, $item.FileExtension)
    }
  }

  end {
  }
}
function Repair-MediaFileDateTimeValue() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [psobject[]]$MediaFileRecord,
    [ValidatePattern("^(\+|\-)\d{1,2}:\d{1,2}:\d{1,2}\s\d{1,2}:\d{1,2}:\d{1,2}$")]
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$DateTimeShift
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $mediaFileRecords = @()

    # split date time shift into components
    $shiftMatch = [regex]::Match($DateTimeShift, '(\+|\-)(.*)')
  }

  process {

    # loop through each media file record add to array
    foreach($item in $MediaFileRecord) {
      $mediaFileRecords += $item
    }
  }

  end {

    # create array of property names used in records
    $propertyNames = $mediaFileRecords | Select-Object -ExpandProperty 'DateTimeProperty' -Unique

    # create array of commands to control execution of exiftool
    $commands = @()
    $commands += ('-AllDates{0}={1}' -f $shiftMatch.Groups[1].Value, $shiftMatch.Groups[2].Value) # shifts all date time values the specified amount

    # loop through each date time property name found in records
    foreach ($propertyName in $propertyNames) {
      $commands += ('-{0}{1}={2}' -f $propertyName, $shiftMatch.Groups[1].Value, $shiftMatch.Groups[2].Value) # shifts date time values the specified amount for the specified property
    }

    $commands += '-overwrite_original_in_place' # overwrites original file instead of creating a backup copy on disk

    # create new arg file
    $argFilePath = New-ExifToolArgFile -Command ($commands) -MediaFilePath $mediaFileRecords.FullName

    # invoke exif tool
    $results = Invoke-ExifTool -Arguments ('-@', $argFilePath)

    # if exif tool invocation was successful
    if ($results.Success) {
      Write-Output $results.Output
    }
    else {
      Write-Error $results.Output
    }

    # remove arg file
    Remove-ExifToolArgFile -Path $argFilePath
  }
}
function Find-RemovableMediaPath() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding()]

  param (
  )

  begin {
    $ErrorActionPreference = "Stop"
  }

  process {}

  end {

    # look for removable media that is not empty
    $results = Get-CimInstance -ClassName 'Win32_LogicalDisk' | Where-Object {$_.DriveType -eq 2} | Where-Object {$null -ne $_.Size}

    # loop through each result
    foreach ($result in $results) {

      # create new output object
      $pathObject = [pscustomobject]@{
        Path = ('{0}\' -f $result.DeviceID)
      }

      # return object
      Write-Output $pathObject
    }
  }
}
function Import-MediaFile() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding(SupportsShouldProcess)]

  param (
    [Alias('FullName')]
    [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string[]]$Path,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Recurse,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Photo,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Video,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$PhotoDestinationPath='C:\_media\new\photo',
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$VideoDestinationPath='C:\_media\new\video'
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $filterParams = @()
    $filterParams += 'PhotoDestinationPath'
    $filterParams += 'VideoDestinationPath'
    $filterParams += 'WhatIf'

    # cache copy of bound params
    $mediaFileParams = $PSBoundParameters

    # loop through each filter param and remove as needed
    foreach ($item in $filterParams) {
      if ($mediaFileParams.ContainsKey($item)) {
        $mediaFileParams.Remove($item) | Out-Null
      }
    }

    # if path was NOT provided
    if (!$Path) {

      Write-Verbose "Path was not provided, checking for removable drive paths..."

      # get removable media file path
      $paths = Find-RemovableMediaPath  | Select-Object -ExpandProperty 'Path'

      Write-Verbose $paths

      # if paths were found
      if ($paths) {

        # add paths to param list
        $mediaFileParams.Add('Path', $paths)

        # add recurse switch so the full path of the removable drive is searched
        if (!$mediaFileParams.ContainsKey('Recurse')) {
          $mediaFileParams.Add('Recurse', $true)
        }
      }
      else {
        Write-Error "No path was provided and no removable drives were found with media files."
      }
    }
  }

  process {}

  end {

    # get media files
    $mediaFiles = Get-MediaFile @mediaFileParams

    # if media files were found
    if ($mediaFiles) {

      # get media file records
      $mediaFileRecords = $mediaFiles | Get-MediaFileRecord

      # prompt user to confirm impot
      $response = Read-Host -Prompt ('Are you sure you want to import {0} files with a total size of {1:n1}gb?' -f $mediaFileRecords.Count, (($mediaFileRecords | Measure-Object -Property 'Length' -Sum).Sum / 1gb))

      # if yes, proceed
      if ($response -match '^y') {

        # init loop count var
        $i = 0

        # loop through each record
        foreach ($mediaFileRecord in $mediaFileRecords) {

          # update loop count var
          $i += 1

          # assemble child path
          $childPath = '{0}{1}' -f $mediaFileRecord.TimeStampValue, $mediaFileRecord.FileExtension

          # set destination based on media file record type
          if ($mediaFileRecord.Type -eq 'photo') {
            $destinationPath = Join-Path -Path $PhotoDestinationPath -ChildPath $childPath
          }
          else {
            $destinationPath = Join-Path -Path $VideoDestinationPath -ChildPath $childPath
          }

          Write-Progress -Activity 'Importing media files...' -Status $destinationPath -PercentComplete (($i / $mediaFileRecords.Count) * 100)

          # move item to import folder
          Move-Item -Path $mediaFileRecord.FullName -Destination $destinationPath
        }
      }
    }
    else {
      Write-Warning 'No media files were found in the specified path.'
    }
  }
}
function Publish-PhotoFile() {

  <#
    .SYNOPSIS

    .EXAMPLE
  #>
  [CmdletBinding(SupportsShouldProcess)]

  param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
      [string]$SourcePath,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$DestinationRawRootPath='\\nas2\photo\raw',
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [string]$DestinationDevRootPath='\\nas2\photo\dev',
    [Parameter(Mandatory=$false, ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
      [switch]$Recurse
  )

  begin {
    $ErrorActionPreference = "Stop"

    # init vars
    $mediaFileParams = @{}
    $mediaFileParams.Path = $SourcePath
    $mediaFileParams.PhotoRaw = $true
    $mediaFileParams.PhotoDev = $true
    $mediaFileParams.IncludePhotoDataFiles = $true
    if ($Recurse) {
      $mediaFileParams.Recurse = $true
    }

    $photoFileRecords = @()

    $rawExtensions = Get-MediaFileExtension -PhotoRaw
    $devExtensions = Get-MediaFileExtension -PhotoDev

    # find all photo files
    $photoFiles = Get-MediaFile @mediaFileParams

    # loop through each file
    foreach ($photoFile in $photoFiles) {

      Write-Verbose ('Processing file name {0}' -f $photoFile.Name)

      # determine type of photo extension and set flags
      $isRaw = ($photoFile.Extension -in $rawExtensions)
      $isDev = ($photoFile.Extension -in $devExtensions)

      # search for existing record by base name
      $resultRecord = $photoFileRecords | Where-Object {$_.SourceFileBaseName -eq $photoFile.BaseName}

      # if record was found, update it
      if ($resultRecord) {

        if ($isRaw) {
          $resultRecord.RawFileName = $photoFile.Name
        }
        elseif ($isDev) {
          $resultRecord.DevFileName = $photoFile.Name
        }
        else {
          $resultRecord.DataFileName = $photoFile.Name
        }
      }
      else {

        # create new output object
        $photoFileRecord = [pscustomobject]@{
          SourceDirectoryPath = $photoFile.DirectoryName
          SourceDirectoryName = (Split-Path -Path $photoFile.DirectoryName -Leaf)
          SourceFileBaseName = $photoFile.BaseName
          Year = (Split-Path -Path $photoFile.DirectoryName -Leaf) -replace '(\d{4})(-.*)', '$1'
          RawFileName = $null
          DevFileName = $null
          DataFileName = $null
        }

        if ($isRaw) {
          $photoFileRecord.RawFileName = $photoFile.Name
        }
        elseif ($isDev) {
          $photoFileRecord.DevFileName = $photoFile.Name
        }
        else {
          $photoFileRecord.DataFileName = $photoFile.Name
        }

        # add item to array
        $photoFileRecords += $photoFileRecord
      }
    }

    # find records that don't have a year value
    $results = ($photoFileRecords | Where-Object {$null -eq $_.Year})

    # if found, display them and write an error
    if ($results) {
      Write-Output $results
      Write-Error ('Some records did not have a `"Year`" value.')
    }

    # find records that have a raw file
    $results = ($photoFileRecords | Where-Object {$null -eq $_.Year})

    # if found, display them and write an error
    if ($results) {
      Write-Output $results
      Write-Error ('Some records did not have a `"Year`" value.')
    }

  }

  process {}

  end {
    Write-Output $photoFileRecords
  }
}

Export-ModuleMember *