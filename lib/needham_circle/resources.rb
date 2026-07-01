# frozen_string_literal: true

module NeedhamCircle
  # Static community resource directory rendered on the /resources page.
  module Resources
    # A single resource row. `link_href` is the explicit destination for web/
    # email contacts; phone-number contacts leave it nil and derive a tel: link
    # from the number text.
    Entry =
      Struct.new(:name, :description, :contact, :link_href, keyword_init: true) do
        # The URL the contact links to: an explicit link, or a tel: link derived
        # from a phone-number contact. Returns nil if neither applies.
        #: () -> String?
        def href
          link_href || phone_href
        end

        # Web links open in a new tab; mailto/tel links stay in-page.
        #: () -> bool
        def external?
          !!href&.start_with?("http")
        end

        # A short, uniform label for the link, so the contact column stays tidy
        # and aligned. The actual value lives in the href (and a title tooltip).
        #: () -> String
        def link_label
          return "Phone" if href&.start_with?("tel:")
          return "Email" if href&.start_with?("mailto:")
          return "Map" if href&.include?("maps.google.")
          "Website"
        end

        private

        # Builds a tel: link from a contact like "(781) 444-2415".
        #: () -> String?
        def phone_href
          digits = contact.gsub(/\D/, "")
          digits.empty? ? nil : "tel:+1#{digits}"
        end
      end

    # A titled group of entries. `name_heading` and `contact_heading` label the
    # first and third table columns, which differ between sections.
    Section = Struct.new(:title, :name_heading, :contact_heading, :entries, keyword_init: true)

    SECTIONS = [
      Section.new(
        title: "Town Offices & Resources",
        name_heading: "Department / Resource",
        contact_heading: "Contact",
        entries: [
          Entry.new(
            name: "Town Manager's Office",
            description: "Manages daily town operations, implements Select Board policies, and oversees municipal administration.",
            contact: "Town Manager Page",
            link_href: "https://www.needhamma.gov/2577/Town-Manager"
          ),
          Entry.new(
            name: "Town Clerk's Office",
            description: "Handles vital records, dog licensing, public records requests, voter registration, and election administration.",
            contact: "Town Clerk Page",
            link_href: "https://www.needhamma.gov/77/Town-Clerk"
          ),
          Entry.new(
            name: "Public Safety (Police & Fire)",
            description: "Provides 24-hour emergency response, community policing dashboards, and fire prevention services.",
            contact: "Public Safety Center",
            link_href: "https://www.needhamma.gov/78/Police"
          ),
          Entry.new(
            name: "Department of Public Works (DPW)",
            description: "Maintains town infrastructure, manages water/sewer utilities, and handles the Recycling & Transfer Station (RTS).",
            contact: "DPW Portal",
            link_href: "https://www.needhamma.gov/5698/Public-Works"
          ),
          Entry.new(
            name: "Needham Public Library",
            description: "Provides a diverse collection of media, community programming, digital learning resources, and research spaces.",
            contact: "Library Website",
            link_href: "https://needhamlibrary.org/"
          ),
          Entry.new(
            name: "Youth & Family Services",
            description: "Delivers mental health counseling, youth support programs, and community-based social services for families.",
            contact: "Youth & Family Services",
            link_href: "https://www.needhamma.gov/79/Youth-Family-Services"
          ),
          Entry.new(
            name: "Council on Aging",
            description: "Supports independent living and provides recreational, wellness, and educational resources at The Center at the Heights.",
            contact: "Council on Aging",
            link_href: "https://www.needhamma.gov/519/Council-on-Aging"
          ),
          Entry.new(
            name: "Town Boards & Committees",
            description: "Offers opportunities for residents to volunteer and serve on local appointed or elected municipal boards.",
            contact: "Committee Vacancies",
            link_href: "https://www.needhamma.gov/497/Boards-Commissions-Committees"
          ),
          Entry.new(
            name: "Town Meeting Information",
            description: "Explains the structure, current warrants, and member lists for Needham's representative local legislature.",
            contact: "Town Meeting Portal",
            link_href: "https://www.needhamma.gov/1831/Town-Meeting-Members"
          ),
          Entry.new(
            name: "\"News You Need(ham)\"",
            description: "The official weekly digital newsletter keeping residents updated on town projects, alerts, and municipal events.",
            contact: "Newsletter Sign-Up",
            link_href: "https://needhamma.us1.list-manage.com/subscribe?u=713dda0f2d48ad06984d25f79&id=04d5ff000d"
          )
        ]
      ),
      Section.new(
        title: "Affinity Groups",
        name_heading: "Group / Organization",
        contact_heading: "Contact",
        entries: [
          Entry.new(
            name: "Needham Diversity Initiative (NDI)",
            description: "Promotes a diverse and inclusive community through public celebrations, educational workshops, and cultural events.",
            contact: "needhamdiversity.org",
            link_href: "https://needhamdiversity.org/"
          ),
          Entry.new(
            name: "Indian Community of Needham (ICON)",
            description: "Brings together the local South Asian community to share cultural traditions and host community celebrations like Holi.",
            contact: "iconeedham.org",
            link_href: "https://www.iconeedham.org/"
          ),
          Entry.new(
            name: "Needham Council for Arts & Culture",
            description: "Cultivates local artistic expression by dispensing public grants and promoting cultural equity across town.",
            contact: "needhamartsandculture@gmail.com",
            link_href: "https://www.needhamma.gov/1111/Needham-Council-for-Arts-Culture"
          ),
          Entry.new(
            name: "Needham Women's Club",
            description: "Connects civic-minded women together to support local community development, philanthropy, and social fellowship.",
            contact: "needhamwomensclub.org",
            link_href: "https://needhamwomensclub.org/"
          )
        ]
      ),
      Section.new(
        title: "Nonprofits",
        name_heading: "Nonprofit Organization",
        contact_heading: "Contact",
        entries: [
          Entry.new(
            name: "Needham Community Council",
            description: "Supports local residents with under-met health, educational, or food needs via a thrift shop, food pantry, and tutoring.",
            contact: "(781) 444-2415"
          ),
          Entry.new(
            name: "Circle of Hope",
            description: "Provides individuals and families experiencing homelessness with clean clothing and essential hygiene supplies.",
            contact: "(781) 444-7474"
          ),
          Entry.new(
            name: "Plugged In Band Program",
            description: "Uses music education to build an inclusive community where youth learn to play in bands and support charities.",
            contact: "pluggedinband.org",
            link_href: "https://www.pluggedinband.org/"
          ),
          Entry.new(
            name: "Charles River Center",
            description: "Offers advocacy, housing, and employment services to children and adults with developmental disabilities.",
            contact: "charlesrivercenter.org",
            link_href: "https://www.charlesrivercenter.org/"
          )
        ]
      ),
      Section.new(
        title: "Parks & Public Spaces",
        name_heading: "Park / Space",
        contact_heading: "Location",
        entries: [
          Entry.new(
            name: "DeFazio Park",
            description: "A massive athletic hub featuring turf fields, a running track, multi-purpose grass spaces, and a tot-lot playground.",
            contact: "Google Maps",
            link_href: "https://maps.google.com/?q=DeFazio+Park+Needham+MA"
          ),
          Entry.new(
            name: "Memorial Park",
            description: "Centrally located park featuring a beautiful community gazebo, walking paths, a turf diamond, and a field house.",
            contact: "Google Maps",
            link_href: "https://maps.google.com/?q=Memorial+Park+Needham+MA"
          ),
          Entry.new(
            name: "Greene's Field",
            description: "A highly accessible neighborhood destination equipped with a baseball diamond, green lawn space, and a vibrant playground.",
            contact: "Google Maps",
            link_href: "https://maps.google.com/?q=Greene%27s+Field+Needham+MA"
          ),
          Entry.new(
            name: "Cricket Field",
            description: "A popular community green space offering grass sports fields, open recreational areas, and a family-friendly playground.",
            contact: "Google Maps",
            link_href: "https://maps.google.com/?q=Cricket+Field+Needham+MA"
          ),
          Entry.new(
            name: "Mills Field",
            description: "Features well-maintained tennis courts, a baseball diamond, an open green lawn, and dedicated children's play areas.",
            contact: "Google Maps",
            link_href: "https://maps.google.com/?q=Mills+Field+Needham+MA"
          )
        ]
      )
    ].freeze
  end
end
