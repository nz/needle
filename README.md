# Needle::Search

Needle: The sharpest and simplest way to search in Rails. It is highly opinionated, to speed up your setup, but flexible enough to get out of your way for use cases when you develop opinions of your own.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'needle-search'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install needle-search

## Quick Start

Needle is highly opinionated, and optimized for the most absurdly quick start possible. All you need to do is add the gem to your Gemfile, reindex your data, and start searching!

Add the gem to your Gemfile:

```ruby
gem 'needle-search'
```

Install the gem with Bundler:

    $ bundle

Index your data:

    $ rake needle:index

Search all of your documents:

```ruby
class ApplicationController
  def search
    @search = Needle.search(params[:q])
  end
end
```

Search only within a certain model:

```ruby
class ArticlesController < ApplicationController
  def index
    if params[:q]
      @search = Article.search(params[:q])
      @articles = @search.results
    else
      @articles = Articles.all
    end
  end
end
```

## Data model

Needle supports the Lucene-based search engines Solr and Elasticsearch. As such, it is advantageous to understand the Lucene data model before we get into more detailed configuration and usage.

* **Index:** Analogous to a SQL database, an Index is your top-level unit of data storage. The data for an index may be split across many _shards_ and thus divided across multiple servers for scalability and write performance. Each shard may have zero or more _replicas_ for increased availability and search performance.
* **Alias:** An Alias is a kind of pointer to one or more indices. Search requests sent to an Alias are distributed to all of its indices. Aliases enable useful operational conveniences such as flexible temporal sharding, and zero-downtime "hot" reindexing.
* **Document:** An Index contains many Documents. A document is analogous to a SQL row, or an ActiveRecord object in Rails. Documents in Lucene are stored in a "flat" architecture, with no built-in relationships between documents. However, it is conventional to assign a _type_ to each, corresponding to the original object's model or SQL table.
* **Field:** A Document has many fields, starting with an `id` and a `type` field to correlate the Lucene document with the object in your primary database that it represents.
* **Field type:**
  * Text: Typically a multi-word string value, which is _tokenized_ into smaller strings called "tokens," or "terms." Each token is then _analyzed_ according to conventional or configurable set of rules to generate normalized forms of each term to match subsequent search queries.
  * String: A scalar string value not subject to analysis, but stored verbatim. Useful for filtering or faceting using the literal scalar value
  * Integer
  * Float
  * Location

## Configuration

### Choosing which models and fields to index.

Needle defaults to making most of your data searchable, making an effort to exclude some common sensitive information. You may want to customize exactly which models should be indexed and made searchable.

```ruby
Needle.searchable.include_models = :all     # :all, or an array of classes
Needle.searchable.exclude_models = [ User ] # nil, or an Array of classes, strings or regular expressions
Needle.searchable.include_fields = :all     # :all, or an explicit array of field names
Needle.searchable.exclude_fields = [ /password/, /digest/, /email/ ] # nil, or an array of strings or regular expressions
```

For example, a flexible approach that includes all models, and whitelists the allowed fields with explicit field names.

```ruby
Needle.searchable.include_fields = %w(title name body excerpt)
```

### Configuring text and term analysis.

**TODO.**

> I confess this is a bit tricky to model independently between Solr and Elasticsearch. This is one place where we are playing to the lowest common denomintor (Solr) in terms of API.
>
> That said, the Sunspot-style approach of creating a handful of pre-defined field types (Solr) or analyzers (Elasticsearch), then using a field naming convention (Solr) or mapping (Elasticsearch) should actually work pretty well in practice. It's actually pretty stunning how widely a common analysis configuration can be used.
> 
> Part of the trick will be sufficiently documenting and exposing these decisions to get out of the way when it becomes necessary to customize these defaults.
 
### Index sharding and replication strategies

Needle uses different strategies for sharding and replication, based on the environment. For development and test environments, Needle uses one index with one shard (see "fixed" sharding, below). For staging and production, Needle uses a kind of temporal sharding based on the number of documents per model, to ensure consistent distribution as your application grows.

To facilitate "hot" reindexing, Needle also scopes all index names with a global index version. As your use cases get to be more sophisticated, you may find yourself needing to make changes to your analysis settings. Incrementing the index version allows you to create new indexes and reindex into them in parallel with existing indexes.

By default, Needle will retain one previous version in most environments, which you may optionally clean up manually. Or you can manually specify the number of previous versions to retain.

```ruby
config.needle.index_version = 1
config.needle.index_version_retention = 1
```

#### Temporal sharding

Temporal sharding creates one index per some fixed unit of time, or number of documents. In production, Needle defaults to using a fixed number of documents per model. This creates roughly similarly-sized shards throughout your search engine cluster over time.

For your capacity planning purposes, the total number of shards used in the cluster will be based on the number of models in your application and the average size of each temporal index. More precisely, you will want to plan for $\sum_{model} model.count / 100,000$

An example of model- and quantity-based temporal sharding, with one shard and one replica per index:

```ruby
config.needle.sharding_strategy = Needle::ShardingStrategy::TemporalByModelAndQuantity.new(
  shard_size: 100_000,
  shards:     1,
  replicas:   1
)
```

Here is an example of model- and time-based temporal sharding, with three shards and one replica per index. The larger number of shards will help for a higher sustained write throughput.

```ruby
config.needle.sharding_strategy = Needle::ShardingStrategy::TemporalByModelAndTime.new(
  period:   Proc.new { |record| record.created_at / 1.week },
  shards:   3,
  replicas: 1
)
```

#### Fixed sharding

Fixed sharding strategy creates a single index per environment, with a specified number of shards and replicas. This is Needle's default strategy for `development` and `test` environments, where index sizes are generally expected to be small, and production performance and replication requirements are less of a consideration.

Here is an example using the fixed index strategy with one shard and zero replicas.

```ruby
config.needle.index_strategy = Needle::IndexStrategy::Fixed.new(
  shards:   1,
  replicas: 0
)
```

For illustration, these are what the API requests to an Elasticsearch server would look like to set up the index and its alias.

    $ curl -X POST http://localhost:9200/application-development-1 -d '{
      "settings": {
        "index": {
          "number_of_shards":   1,
          "number_of_replicas": 0
        }
      }
    }'
    
    $ curl -X POST http://localhost:9200/_aliases -d '{
      "actions": [{ "add": {
        "index": "application-development-1",
        "alias": "application-development"
      }}]
    }'


## Usage

### Full data import

To import all of your data in batches, you can use a rake task:

    $ rake needle:import

Or you can use the following method in Ruby:

```ruby
Needle.import
```

###### How it works:

Needle first starts an agent in its own thread which is responsible for queueing and batching the updates to be sent to your index. It then asks your application's index sharding strategy for a list of all of the current indices. For each index, it starts another thread to fetch and prepare the documents for indexing.

This approach is a more optimal approach for Lucene search engines. It strikes a balance between parallelism, which is faster for reading and formatting your documents, and serialized batches per index, which is faster and more optimal for updating a Lucene index.

### Incremental updates

Whenever your objects change, Needle will automatically update your index. To preserve performance and operational reliability, Needle is designed to queue your updates and send them in asynchronous batches.

Needle uses a similar batching agent approach for incremental updates, like it does for full data imports. By default it runs an import agent per process with in-memory queuing, which is a pragmatic design choice that works well for relatively small applications.

For larger applications, you will want to run the needle import agent in a process of its own, with a reliable queue to collect the updates from your application processes.

    $ rake needle:import:agent

Configuring a queue:

```ruby
config.needle.queue = Needle::Queue::Redis.new($redis)
```

###### How the agent works

    # As records are created or updated, an after_commit hook adds them to the relevant per-index queue.
    Needle.index_strategy << record
    
    # The import agent runs in a loop, checking for indices with pending updates.
    # Each index with pending updates is given its own thread to pull documents
    # from its queue, serialize them into a batch, and send the update to the index.
    #
    while true
      Needle.index_strategy.enumerate_indices.each do |index|
        if index.updates_pending? && !index.import_agent.running?
          index.import_agent.run
        end
      end
      sleep 1
    end

### Searching your documents

Needle's default search method is designed to run a basic full-text query that works well with most use cases.

Search all of your documents:

```ruby
class ApplicationController
  def search
    @search = Needle.search(params[:q])
  end
end
```

Search only within a certain model:

```ruby
class ArticlesController < ApplicationController
  def index
    if params[:q]
      @search = Article.search(params[:q])
      @articles = @search.results
    else
      @articles = Articles.all
    end
  end
end
```

When you need to run more complex searches, Needle gets out of your way, and exposes its lower-level client for handling communication with either Solr or Elasticsearch. These lower-level clients (RSolr and Stretcher) provide as generic an interface as possible to each respective API, allowing you to send parameters that are structured in your application with simple Ruby hashes.

This is an intentional design decision for Needle, meant to prevent a tight coupling between Needle's API and the API of the search engine that you are using. This helps your application adapt to API changes within your search engine, without requiring updates to Needle's own APIs.

The correlary, and main caveat here, is that you need to learn the API of the search engine you are working with, in order to implement your search queries in the first place. Furthermore, your application code will create a strong coupling with the API of your search engine of choice.

That said, learning some of your search engine's underlying API is almost unavoidable for any non-trivial usage. And any coupling between your application logic and your search engine's API is made explicit and left entirely to your control.

##### Solr

```ruby
@search = Article.search({
  q: params[:q],
  qf: [ :title, :body ],
  defType: 'edismax',
  fq: { author_id: params[:author_id] }
})
```

Our Solr connection driver does provide some minimum input sanitization and field name mapping. This is seen in the values for query fields (`qf`), which are translated into a naming convention which serves to match each field to its type. Likewise, the filter query (`fq`) maps the `author_id` field name to its type, sanitizes the input, and assembles a Lucene query for the final value.

Finally, the class-based search method adds an implicit filter query to limit the search to documents of that type.

##### Elasticsearch

```ruby
Article.search({
  query: {
    text: params[:q],
    filds: [ :title, :body ]
  },
  filters: [
    { term: { author_id: params[:author_id] }}
  ]
})
```

The Elasticsearch query adapter is a bit more straightforward. It sanitizes incoming values before transforming the entire hash to JSON. The class-specific search method also executes its search against the `_search` handler for its corresponding type.

*(**TODO:** test for syntactical correctness.)*

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Project goals

### Primary goals

- Highly opinionated where it counts, with trustworthy technical defaults for the quickest quick-start possible.
- Stays out of your way where your subjective decisions are required.
- Integrates with Solr and Elasticsearch.

### Secondary goals

- Optimized for Rails and ActiveRecord, but usable from other ORMs or plain ol' Ruby.
- The broadest possible support for multiple versions of Rails and Ruby.
