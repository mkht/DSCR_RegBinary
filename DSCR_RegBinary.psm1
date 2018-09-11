Enum Mode {
    Overwrite
    Insert
}


[DscResource()]
Class cRegBinary {

    [DSCProperty(Key)]
    [String]
    $Key

    [DSCProperty(Key)]
    [String]
    $ValueName

    [DSCProperty(Mandatory)]
    [String]
    $ValueData

    [DSCProperty()]
    [Mode]
    $Mode = [Mode]::Overwrite

    [DSCProperty(Key)]
    [int]
    $Offset

    [DSCProperty()]
    [string]
    $DefaultValue

    [cRegBinary] Get() {
        $private:RegKey = Get-Item -LiteralPath ('Registry::' + $this.Key) -ErrorAction SilentlyContinue

        if ($private:RegKey) {
            if ($null -eq $private:RegKey.GetValue($this.ValueName)) {
                Write-Verbose ('The registry value {0} is missing.' -f $this.ValueName)
                $this.ValueData = $null
            }
            elseif ($private:RegKey.GetValueKind($this.ValueName) -ne 'Binary') {
                Write-Verbose ('The specified registry value is found, but the value kind is not a REG_BINARY.')
                $this.ValueData = $null
            }
            else {
                Write-Verbose ('The specified registry binary value is found')
                $this.ValueData = [System.BitConverter]::ToString($private:RegKey.GetValue($this.ValueName)).Replace('-', [string]::Empty)
            }
        }
        else {
            Write-Verbose ('The registry key {0} is missing.' -f $this.Key)
            $this.ValueData = $null
        }

        return $this
    }


    [bool] Test() {
        $desiredValue = $this.CreateNewValue()
        $currentValue = $this.Get().ValueData

        #Write-Verbose ('Current Value: {0} / Desired Value: {1}' -f $currentValue, $desiredValue)

        return ($desiredValue -eq $currentValue)
    }


    [void] Set() {
        $path = ('Registry::' + $this.Key)
        $desiredValue = $this.CreateNewValue()

        try {
            [Byte[]]$newValueBytes = for ($i = 0; $i -lt $desiredValue.Length; $i += 2) {
                [Convert]::ToByte(([string]$desiredValue[$i] + [string]$desiredValue[$i + 1]), 16)
            }
        }
        catch {
            Write-Error ('The Value "{0}" could not be converted to binary' -f $desiredValue)
            return
        }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose ('Creating new registry key: {0}' -f $this.Key)
            New-Item -Path $path -Force >$null
        }

        if (Get-ItemProperty -LiteralPath $path -Name $this.ValueName -ErrorAction SilentlyContinue) {
            Write-Verbose ('Set registry Value: {0}' -f $desiredValue)
            Set-ItemProperty -LiteralPath $path -Name $this.ValueName -Value $newValueBytes
        }
        else {
            Write-Verbose ('Create registry Value: {0}' -f $desiredValue)
            New-ItemProperty -LiteralPath $path -Name $this.ValueName -Value $newValueBytes
        }
    }


    Hidden [string] CreateNewValue() {
        $private:RegKey = Get-Item -LiteralPath ('Registry::' + $this.Key) -ErrorAction SilentlyContinue

        if ((-not $private:RegKey) -or ($null -eq $private:RegKey.GetValue($this.ValueName)) -or ($private:RegKey.GetValueKind($this.ValueName) -ne 'Binary')) {
            Write-Verbose ('Specified registry value is not found or not a REG_BINARY type.')

            if (-not [string]::IsNullOrEmpty($this.DefaultValue)) {
                Write-Verbose ('The registry value will be set to DefaultValue')
                $private:DefaultValue = $this.DefaultValue

                if (($private:DefaultValue.Length % 2) -eq 1) {
                    $private:DefaultValue = $private:DefaultValue + '0'
                }

                return $private:DefaultValue
            }
        }

        try {
            [string]$originalValue = [System.BitConverter]::ToString($private:RegKey.GetValue($this.ValueName)).Replace('-', [string]::Empty)
        }
        catch {
            [string]$originalValue = [string]::Empty
        }

        [string]$newValue = $originalValue

        switch ($this.Mode) {
            'Overwrite' {
                if ($this.Offset -gt $originalValue.Length) {
                    # Zero padding
                    $span = (1..($this.Offset - $originalValue.Length)).ForEach( {'0'} ) -join [string]::Empty
                    $newValue = $originalValue + $span + $this.ValueData
                }
                elseif (($this.Offset + $this.ValueData.Length) -gt $originalValue.Length) {
                    $newValue = $originalValue.Substring(0, $this.Offset) + $this.ValueData
                }
                else {
                    $newValue = $originalValue.Substring(0, $this.Offset) + $this.ValueData + $originalValue.Substring($this.Offset + $this.ValueData.Length)
                }
            }

            'Insert' {
                if ($this.Offset -gt $originalValue.Length) {
                    # Zero padding
                    $span = (1..($this.Offset - $originalValue.Length)).ForEach( {'0'} ) -join [string]::Empty
                    $newValue = $originalValue + $span + $this.ValueData
                }
                else {
                    $sb = New-Object -TypeName System.Text.StringBuilder -ArgumentList $originalValue
                    $newValue = $sb.Insert($this.Offset, $this.ValueData).ToString()
                }
            }
        }

        if (($newValue.Length % 2) -eq 1) {
            $newValue = $newValue + '0'
        }

        Write-Verbose ('The registry value will be set to "{0}"' -f $newValue)

        return $newValue
    }
}
