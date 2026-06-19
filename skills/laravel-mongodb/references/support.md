# Support and Issue Reporting

Report issues to the repository that owns the layer where the bug occurs:

| Layer                                            | Repository |
|--------------------------------------------------|---|
| Eloquent integration, Laravel-specific behaviour | [mongodb/laravel-mongodb](https://github.com/mongodb/laravel-mongodb/issues) |
| PHP query API, BSON, GridFS                      | [mongodb/mongo-php-library](https://github.com/mongodb/mongo-php-library/issues) |
| C driver, connection, PHP extension              | [mongodb/mongo-php-driver](https://github.com/mongodb/mongo-php-driver/issues) |
| Documentation                                    | [mongodb/docs](https://github.com/mongodb/docs/issues) |

## Diagnosing the layer

- **`MongoDB\Laravel\*` class or Eloquent method** → `laravel-mongodb`
- **`MongoDB\Driver\*` or `ext-mongodb` error** → `mongo-php-driver`
- **`MongoDB\*` (no `Laravel`) class** → `mongo-php-library`
- **Wrong page in the docs** → `docs`
