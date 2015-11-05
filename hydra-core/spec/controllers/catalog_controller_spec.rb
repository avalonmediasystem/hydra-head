require 'spec_helper'

describe CatalogController do

  before do
    session[:user]='bob'
  end

  it "should use CatalogController" do
    expect(controller).to be_an_instance_of CatalogController
  end

  describe "configuration" do
    let(:config) { CatalogController.blacklight_config }
    describe "search_builder_class" do
      subject {config.search_builder_class }
      it { is_expected.to eq Hydra::SearchBuilder }
    end
  end

  describe "Paths Generated by Custom Routes:" do
    # paths generated by custom routes
    it "should map {:controller=>'catalog', :action=>'index'} to GET /catalog" do
      expect(get: "/catalog").to route_to(controller: 'catalog', action: 'index')
    end
    it "should map {:controller=>'catalog', :action=>'show', :id=>'test:3'} to GET /catalog/test:3" do
      expect(get: "/catalog/test:3").to route_to(controller: 'catalog', action: 'show', id: 'test:3')
    end

    it "maps solr_document_path" do
      expect(solr_document_path("test:3")).to eq '/catalog/test:3'
    end
  end

  describe "index" do
    describe "access controls" do
      before(:all) do
        fq = "read_access_group_ssim:public OR edit_access_group_ssim:public OR discover_access_group_ssim:public"
        solr_opts = { fq: fq }
        response = ActiveFedora::SolrService.instance.conn.get('select', params: solr_opts)
        @public_only_results = Blacklight::Solr::Response.new(response, solr_opts)
      end

      it "should only return public documents if role does not have permissions" do
        allow(controller).to receive(:current_user).and_return(nil)
        get :index
        expect(assigns(:document_list).count).to eq @public_only_results.docs.count
      end

      it "should return documents if the group names need to be escaped" do
        allow(RoleMapper).to receive(:roles).and_return(["abc/123","cde/567"])
        get :index
        expect(assigns(:document_list).count).to eq @public_only_results.docs.count
      end
    end
  end

  describe "content negotiation" do
    describe "show" do
      before do
        allow(controller).to receive(:enforce_show_permissions)
      end
      context "with no asset" do
        it "should return a not found response code" do
          get 'show', :id => "test", :format => :nt

          expect(response).to be_not_found
        end
      end
      context "with an asset" do
        let(:type) { RDF::URI("http://example.org/example") }
        let(:related_uri) { related.rdf_subject }
        let(:asset) do
          ActiveFedora::Base.create do |g|
            g.resource << [g.rdf_subject, RDF::Vocab::DC.title, "Test Title"]
            g.resource << [g.rdf_subject, RDF.type, type]
            g.resource << [g.rdf_subject, RDF::Vocab::DC.isReferencedBy, related_uri]
          end
        end
        let(:related) do
          ActiveFedora::Base.create
        end
        it "should be able to negotiate jsonld" do
          get 'show', :id => asset.id, :format => :jsonld

          expect(response).to be_success
          expect(response.headers['Content-Type']).to include("application/ld+json")
          graph = RDF::Reader.for(:jsonld).new(response.body)
          expect(graph.statements.to_a.length).to eq 3
        end
        it "should be able to negotiate ttl" do
          get 'show', :id => asset.id, :format => :ttl
          
          expect(response).to be_success
          graph = RDF::Reader.for(:ttl).new(response.body)
          expect(graph.statements.to_a.length).to eq 3
        end
        it "should return an n-triples graph with just the content put in" do
          get 'show', :id => asset.id, :format => :nt

          graph = RDF::Reader.for(:ntriples).new(response.body)
          statements = graph.statements.to_a
          expect(statements.length).to eq 3
          expect(statements.first.subject).to eq asset.rdf_subject
        end
        context "with a configured subject converter" do
          before do
            Hydra.config.id_to_resource_uri = lambda { |id| "http://hydra.box/catalog/#{id}" }
            get 'show', :id => asset.id, :format => :nt
          end
          it "should convert it" do
            graph = RDF::Graph.new << RDF::Reader.for(:ntriples).new(response.body)
            title_statement = graph.query([nil, RDF::DC.title, nil]).first
            related_statement = graph.query([nil, RDF::DC.isReferencedBy, nil]).first
            expect(title_statement.subject).to eq RDF::URI("http://hydra.box/catalog/#{asset.id}")
            expect(related_statement.object).to eq RDF::URI("http://hydra.box/catalog/#{related.id}")
          end
        end
      end
    end
  end

  describe "filters" do
    describe "show" do
      it "should trigger enforce_show_permissions" do
        allow(controller).to receive(:current_user).and_return(nil)
        expect(controller).to receive(:enforce_show_permissions)
        get :show, id: 'test:3'
      end
    end
  end

end
