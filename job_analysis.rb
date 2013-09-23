# Analysis tools for job logs.
module JobAnalysis
  def log_key
    "#{ident}_log"
  end

  def checkpoint_key
    'last_analyzed_log_entry'
  end

  def reset_analysis
    redis.multi do
      redis.hdel(ident, checkpoint_key)
      response_buckets.each { |_, bucket, _| redis.hdel(ident, bucket) }
    end
  end

  def analyze
    start = redis.hget(ident, checkpoint_key).to_f
    resps = redis.zrangebyscore(log_key, "(#{start}", '+inf', :with_scores => true)

    last = resps.last.last

    redis.pipelined do
      resps.each do |p, _|
        entry = JSON.parse(p)
        wget_code = entry['wget_code']
        response_code = entry['response_code'].to_i

        if wget_code != 'RETRFINISHED'
          if response_code == 0 || response_code >= 500
            incr_error_count
          end
        end

        response_buckets.each do |range, bucket, _|
          if range.include?(response_code)
            redis.hincrby(ident, bucket, 1)
            break
          end
        end
      end

      redis.hset(ident, checkpoint_key, last)
    end

    # suppress redis.pipelined return value; we don't care about it
    true
  end
end
