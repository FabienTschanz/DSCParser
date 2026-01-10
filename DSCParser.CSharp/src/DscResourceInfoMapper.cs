using System;
using System.Collections.Generic;
using ImplementedAsType = Microsoft.PowerShell.DesiredStateConfiguration.ImplementedAsType;
using DscResourceInfo = Microsoft.PowerShell.DesiredStateConfiguration.DscResourceInfo;
using DscResourcePropertyInfo = Microsoft.PowerShell.DesiredStateConfiguration.DscResourcePropertyInfo;

namespace DSCParser.CSharp
{
    internal sealed class DscResourceInfoMapper
    {
        public static DscResourceInfo MapPSObjectToResourceInfo(dynamic psObject)
        {
            if (psObject is null) throw new ArgumentNullException(nameof(psObject));

            DscResourceInfo resourceInfo = new();
            resourceInfo.ResourceType = psObject.ResourceType;
            resourceInfo.CompanyName = psObject.CompanyName;
            resourceInfo.FriendlyName = psObject.FriendlyName;
            resourceInfo.Module = psObject.Module;
            resourceInfo.Path = psObject.Path;
            resourceInfo.ParentPath = psObject.ParentPath;
            resourceInfo.ImplementedAs = Enum.Parse(typeof(ImplementedAsType), psObject.ImplementedAs.ToString());
            resourceInfo.Name = psObject.Name;

            List<DscResourcePropertyInfo> props = [];
            foreach (object obj in psObject.Properties)
            {
                props.Add(MapToDscResourcePropertyInfo(obj));
            }
            resourceInfo.UpdateProperties(props);

            return resourceInfo;
        }

        public static DscResourcePropertyInfo MapToDscResourcePropertyInfo(dynamic psObjectPropery)
        {
            DscResourcePropertyInfo propertyInfo = new();
            propertyInfo.Name = psObjectPropery.Name;
            propertyInfo.PropertyType = psObjectPropery.PropertyType;
            propertyInfo.IsMandatory = psObjectPropery.IsMandatory;

            List<string> newValues = [];
            foreach (string value in psObjectPropery.Values)
            {
                newValues.Add(value);
            }
            propertyInfo.Values = newValues;
            return propertyInfo;
        }
    }
}