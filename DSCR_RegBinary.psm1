Enum Mode{
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


    [cRegBinary] Get() {
        $private:RegKey = Get-Item -LiteralPath ('Registry::' + $this.Key) -ErrorAction SilentlyContinue

        if ($private:RegKey) {
            if ($private:RegKey.GetValueKind($this.ValueName) -ne 'Binary') {
                $this.ValueData = $null
            }
            else {
                $this.ValueData = [System.BitConverter]::ToString($private:RegKey.GetValue($this.ValueName)).Replace('-', [string]::Empty)
            }
        }
        else {
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

        [Byte[]]$newValueBytes = for ($i = 0; $i -lt $desiredValue.Length; $i += 2) {
            [Convert]::ToByte(([string]$desiredValue[$i] + [string]$desiredValue[$i + 1]), 16)
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

        if (-not $private:RegKey) {
            return $this.ValueData
        }
        elseif ($private:RegKey.GetValueKind($this.ValueName) -ne 'Binary') {
            return $this.ValueData
        }

        [string]$originalValue = [System.BitConverter]::ToString($private:RegKey.GetValue($this.ValueName)).Replace('-', [string]::Empty)
        [string]$newValue = $originalValue

        switch ($this.Mode) {
            'Overwrite' {
                if ($this.Offset -gt $originalValue.Length) {
                    # Zero padding
                    $span = (1..($originalValue.Length - $this.Offset)).ForEach( {'0'} ) -join [string]::Empty
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
                    $span = (1..($originalValue.Length - $this.Offset)).ForEach( {'0'}) -join [string]::Empty
                    $newValue = $originalValue + $span + $this.ValueData
                }
                else {
                    $sb = New-Object -TypeName System.Text.StringBuilder -ArgumentList $originalValue
                    $newValue = $sb.Insert($this.Offset, $this.ValueData).ToString()
                }
            }
        }

        return $newValue
    }
}
