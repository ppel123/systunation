function Convert-EntraRoleIdToSid {
    param([guid]$RoleTemplateId)
    $bytes = $RoleTemplateId.ToByteArray()
    'S-1-12-1-' + ((0, 4, 8, 12 | ForEach-Object {
        [BitConverter]::ToUInt32($bytes, $_)
    }) -join '-')
}

# Global Administrator
Convert-EntraRoleIdToSid '62e90394-69f5-4237-9190-012177145e10'

# Azure AD Joined Device Local Administrator
Convert-EntraRoleIdToSid '9f06204d-73c1-4d4c-880a-6edb90606fd8'