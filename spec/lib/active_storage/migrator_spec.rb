require 'rails_helper'
require 'stringio'

RSpec.describe ActiveStorage::Migrator do
  describe '.migrate' do
    let(:from_service_stub) { instance_double(ActiveStorage::Service) }
    let(:to_service_stub) { instance_double(ActiveStorage::Service) }

    before do
      allow(ActiveStorage::Service).to receive(:configure).with('local', any_args).and_return(from_service_stub)
      allow(ActiveStorage::Service).to receive(:configure).with('amazon', any_args).and_return(to_service_stub)
    end

    context 'when services are configured correctly' do
      it 'migrates blobs from one service to another' do
        expect(ActiveStorage::Service).to receive(:configure).with('local', any_args)
        expect(described_class).to receive(:migrate_blobs).with('local', 'amazon', should_update_service_name: true)
        expect { described_class.migrate('local', 'amazon') }.not_to raise_error
      end

      it 'passes the service-name update flag to blob migration' do
        expect(described_class).to receive(:migrate_blobs).with('local', 'amazon', should_update_service_name: false)

        described_class.migrate('local', 'amazon', should_update_service_name: false)
      end

      it 'does not override the application logger' do
        allow(described_class).to receive(:migrate_blobs)

        expect(Rails).not_to receive(:logger=)

        described_class.migrate('local', 'amazon')
      end
    end

    context 'when services are not configured correctly' do
      it 'prints an error message' do
        allow(ActiveStorage::Service).to receive(:configure).and_return(nil)
        expect do
          described_class.migrate('random', 'random')
        end.to raise_error(RuntimeError, "Error: The services 'random' or 'random' are not configured correctly.")
      end
    end
  end

  describe '.migrate_blobs' do
    let(:to_service_stub) { instance_double(ActiveStorage::Service) }
    let(:source_blobs) { instance_double(ActiveRecord::Relation, count: 1) }
    let(:blob) { instance_double(ActiveStorage::Blob, id: 1, key: 'blob-key', checksum: 'checksum') }
    let(:io) { StringIO.new('blob-content') }

    before do
      allow(ActiveStorage::Service).to receive(:configure).with(:amazon, any_args).and_return(to_service_stub)
      allow(ActiveStorage::Blob).to receive(:where).with(service_name: 'local').and_return(source_blobs)
      allow(source_blobs).to receive(:find_each).and_yield(blob)
      allow(blob).to receive(:open).and_yield(io)
      allow(blob).to receive(:update!)
      allow(to_service_stub).to receive(:upload)
    end

    it 'migrates blobs regardless of content type' do
      expect(to_service_stub).to receive(:upload).with('blob-key', io, checksum: 'checksum').ordered
      expect(blob).to receive(:update!).with(service_name: 'amazon').ordered

      described_class.migrate_blobs(:local, :amazon, should_update_service_name: true)
    end

    it 'only migrates blobs from the source service' do
      expect(ActiveStorage::Blob).to receive(:where).with(service_name: 'local').and_return(source_blobs)
      expect(source_blobs).to receive(:find_each).and_yield(blob)

      described_class.migrate_blobs(:local, :amazon, should_update_service_name: true)
    end

    it 'skips the blob service update when the flag is disabled' do
      expect(to_service_stub).to receive(:upload).with('blob-key', io, checksum: 'checksum')
      expect(blob).not_to receive(:update!)

      described_class.migrate_blobs(:local, :amazon, should_update_service_name: false)
    end

    it 'skips missing source files and continues migration' do
      missing_blob = instance_double(ActiveStorage::Blob, id: 2, key: 'missing-key')

      allow(source_blobs).to receive(:find_each).and_yield(missing_blob).and_yield(blob)
      allow(missing_blob).to receive(:open).and_raise(ActiveStorage::FileNotFoundError)

      expect(missing_blob).not_to receive(:update!)
      expect(to_service_stub).to receive(:upload).with('blob-key', io, checksum: 'checksum')
      expect(blob).to receive(:update!).with(service_name: 'amazon')

      described_class.migrate_blobs(:local, :amazon, should_update_service_name: true)
    end

    it 'does not update the blob service when upload fails' do
      allow(to_service_stub).to receive(:upload).and_raise(ActiveStorage::IntegrityError)

      expect(blob).not_to receive(:update!)
      expect do
        described_class.migrate_blobs(:local, :amazon, should_update_service_name: true)
      end.to raise_error(ActiveStorage::IntegrityError)
    end
  end
end
