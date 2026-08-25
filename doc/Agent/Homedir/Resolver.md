# Class Agent::Homedir::Resolver <a id="class-Agent-Homedir-Resolver"></a>

|  |  |
| --- | --- |
| **Inherits** | Object |
| **Defined in** | lib/agent/homedir/resolver.rb |

## Constants
### `VALID_OSES` <a id="constant-VALID_OSES"></a> <a id="VALID_OSES-constant"></a>
Not documented.

### `WINDOWS_DRIVE_PATH` <a id="constant-WINDOWS_DRIVE_PATH"></a> <a id="WINDOWS_DRIVE_PATH-constant"></a>
Not documented.

### `WINDOWS_UNC_PATH` <a id="constant-WINDOWS_UNC_PATH"></a> <a id="WINDOWS_UNC_PATH-constant"></a>
Not documented.

## Public Class Methods
### `default_os()` <a id="method-c-default_os"></a> <a id="default_os-class_method"></a>
Not documented.

## Public Instance Methods
### `[] (name)` <a id="method-i--5B-5D"></a> <a id="[]-instance_method"></a>
Not documented.

### `agents()` <a id="method-i-agents"></a> <a id="agents-instance_method"></a>
Not documented.

### `candidates(name)` <a id="method-i-candidates"></a> <a id="candidates-instance_method"></a>
Not documented.

### `home(name)` <a id="method-i-home"></a> <a id="home-instance_method"></a>
Not documented.

### `initialize(env: = ENV.to_h, home: = ENV["HOME"], os: = self.class.default_os, entries: = Registry.entries)` <a id="method-i-initialize"></a> <a id="initialize-instance_method"></a>
- **@return** [Resolver] a new instance of Resolver

### `installed()` <a id="method-i-installed"></a> <a id="installed-instance_method"></a>
Not documented.

### `installed?(name)` <a id="method-i-installed-3F"></a> <a id="installed?-instance_method"></a>
- **@return** [Boolean]

### `names()` <a id="method-i-names"></a> <a id="names-instance_method"></a>
Not documented.
