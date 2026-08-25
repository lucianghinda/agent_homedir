# Class Agent::Homedir::Entry <a id="class-Agent-Homedir-Entry"></a>

|  |  |
| --- | --- |
| **Inherits** | Object |
| **Defined in** | lib/agent/homedir/entry.rb |

## Public Instance Methods
### `candidates()` <a id="method-i-candidates"></a> <a id="candidates-instance_method"></a>
Not documented.

### `home()` <a id="method-i-home"></a> <a id="home-instance_method"></a>
Not documented.

### `initialize(name:, label:, env_override:, verified_on:, resolver:)` <a id="method-i-initialize"></a> <a id="initialize-instance_method"></a>
Equality and hash intentionally cover only public facts. Resolver-specific
caches should key by resolver and agent name.
- **@return** [Entry] a new instance of Entry

### `installed?()` <a id="method-i-installed-3F"></a> <a id="installed?-instance_method"></a>
- **@return** [Boolean]

### `with(**changes)` <a id="method-i-with"></a> <a id="with-instance_method"></a>
Not documented.
