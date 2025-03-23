# Start transcript for logging
$LogPath = "C:\Temp\ImageToBase64Conversion.log"
Start-Transcript -Path $LogPath -Append

function Convert-ImageToBase64 {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ImagePath
    )

    Write-Host "Converting image to Base64: $ImagePath"

    if (-not (Test-Path $ImagePath)) {
        throw "File not found: $ImagePath"
    }

    $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
    $base64String = [System.Convert]::ToBase64String($imageBytes)

    Write-Host "Conversion completed. Base64 string length: $($base64String.Length)"

    return $base64String
}

try {
    # Prompt for image path
    $imagePath = Read-Host "Enter the full path to your image file (e.g., C:\Path\To\Your\Image.ico,png or jpeg or webp)"

    # Convert image to Base64
    $base64String = Convert-ImageToBase64 -ImagePath $imagePath

    # Prompt for output option
    $outputChoice = Read-Host "Do you want to (1) Display the Base64 string or (2) Save it to a file? Enter 1 or 2"

    switch ($outputChoice) {
        "1" {
            Write-Host "`nBase64 string:"
            Write-Host $base64String
        }
        "2" {
            $outputPath = Read-Host "Enter the full path where you want to save the Base64 string (e.g., C:\Path\To\Output\base64output.txt)"
            $base64String | Out-File -FilePath $outputPath
            Write-Host "Base64 string saved to: $outputPath"
        }
        default {
            Write-Host "Invalid choice. The Base64 string will be displayed:"
            Write-Host $base64String
        }
    }

    Write-Host "`nScript execution completed. Log file location: $LogPath"
} catch {
    Write-Error "An error occurred: $_"
} finally {
    Stop-Transcript
}

Read-Host "Press Enter to exit"