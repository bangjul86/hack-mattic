# DefaultPluginSet









## Methods

### getAllFunctionsOfPlugin

```solidity
function getAllFunctionsOfPlugin(string _pluginName) external view returns (struct IPlugin.PluginFunction[])
```

Returns all functions that belong to the given plugin contract.



#### Parameters

| Name | Type | Description |
|---|---|---|
| _pluginName | string | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | IPlugin.PluginFunction[] | undefined |

### getAllPlugins

```solidity
function getAllPlugins() external view returns (struct IPlugin.Plugin[] allPlugins)
```

Returns all plugins stored.




#### Returns

| Name | Type | Description |
|---|---|---|
| allPlugins | IPlugin.Plugin[] | undefined |

### getPlugin

```solidity
function getPlugin(string _pluginName) external view returns (struct IPlugin.Plugin)
```

Returns the plugin metadata and functions for a given plugin.



#### Parameters

| Name | Type | Description |
|---|---|---|
| _pluginName | string | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | IPlugin.Plugin | undefined |

### getPluginForFunction

```solidity
function getPluginForFunction(bytes4 _functionSelector) external view returns (struct IPlugin.PluginMetadata)
```

Returns the plugin metadata for a given function.



#### Parameters

| Name | Type | Description |
|---|---|---|
| _functionSelector | bytes4 | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | IPlugin.PluginMetadata | undefined |

### getPluginImplementation

```solidity
function getPluginImplementation(string _pluginName) external view returns (address)
```

Returns the plugin&#39;s implementation smart contract address.



#### Parameters

| Name | Type | Description |
|---|---|---|
| _pluginName | string | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | address | undefined |

### setPlugin

```solidity
function setPlugin(IPlugin.Plugin _plugin) external nonpayable
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| _plugin | IPlugin.Plugin | undefined |



## Events

### PluginAdded

```solidity
event PluginAdded(address indexed pluginAddress, bytes4 indexed functionSelector, string functionSignature)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| pluginAddress `indexed` | address | undefined |
| functionSelector `indexed` | bytes4 | undefined |
| functionSignature  | string | undefined |

### PluginRemoved

```solidity
event PluginRemoved(address indexed pluginAddress, bytes4 indexed functionSelector, string functionSignature)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| pluginAddress `indexed` | address | undefined |
| functionSelector `indexed` | bytes4 | undefined |
| functionSignature  | string | undefined |

### PluginUpdated

```solidity
event PluginUpdated(address indexed oldPluginAddress, address indexed newPluginAddress, bytes4 indexed functionSelector, string functionSignature)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| oldPluginAddress `indexed` | address | undefined |
| newPluginAddress `indexed` | address | undefined |
| functionSelector `indexed` | bytes4 | undefined |
| functionSignature  | string | undefined |


