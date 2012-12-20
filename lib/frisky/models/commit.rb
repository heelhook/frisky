module Frisky
  module Model
    class Commit < ProxyBase
      attr_accessor :author, :message, :sha, :parents, :repository, :stats, :committer,
                    :files, :tree, :date

      fetch_key id: :id, repository: Proc.new { repository.full_name || repository.name }, sha: :sha
      fetch_autoload :stats, :parents, :message, :sha

      fallback_fetch do |args|
        repo_full_name = args[:repository].full_name if args[:repository].is_a? Repository
        repo_full_name ||= args[:repository]
        Frisky.log.debug "[FALLBACK COMMIT] #{args[:id]} #{repo_full_name} #{args[:sha]}"
        Octokit.commit(repo_full_name, args[:sha])
      end

      after_fallback_fetch do |obj|
        self.author         = Person.soft_fetch(obj.author || obj.commit.author)
        self.committer      = Person.soft_fetch(obj.committer || obj.commit.committer)
        self.message        = obj.commit.message if obj.commit and obj.commit.message
        self.date           = DateTime.parse obj.commit.author.date rescue nil
        self.stats          = obj.stats

        self.parents        = []
        obj.parents.each do |parent|
          parent.repository = self.repository
          self.parents     << Commit.soft_fetch(parent)
        end

        self.files          = []
        obj.files.each do |file|
          file.repository   = self.repository
          file.commit       = self
          self.files       << FileCommit.soft_fetch(repository: self.repository,
                                                    commit: self, path: file.filename)
        end
      end

      proxy_methods :author, :committer, :message, :date, :stats, :parents, :files

      def self.load_from_raw(raw)
        model = super(raw)

        # id/sha, commit.message, repository
        model.sha = raw.sha if raw.respond_to? :sha
        model.sha ||= raw.id if raw.respond_to? :id

        model.repository   = raw.repository if raw.repository.is_a? Repository
        model.repository ||= Repository.soft_fetch(full_name: raw.repository.full_name)

        model.message = raw.message if raw.respond_to? :message
        model.author = Person.soft_fetch(raw.author) if raw.author
        model.author ||= Person.soft_fetch(raw.commit.author) if raw.commit and raw.commit.author
        model.committer = Person.soft_fetch(raw.committer) if raw.committer
        model.committer ||= Person.soft_fetch(raw.commit.committer) if raw.commit and raw.commit.committer
        model
      end
    end
  end
end