use v6;

=begin pod

=head1 Pod::To::Tree

Return a tree of Node:: objects from Perl 6 POD.

=head1 Synopsis

    use Pod::To::Tree;

    say Pod::To::Tree.new.to-tree( $=[0] );

=head1 Documentation

=head2 Motivation

The Perl 6 POD tree works out nicely, overall. There are a few places, however, that if you want to generate HTML you might run into some issues. Walking the tree of an item naively would get you C<< <li> <p> foo </p> </li> >> - one element for the outer L<Pod::Item>, then the L<Pod::Block::Para> inside that, and inside that the content text 'foo'.

It's pretty easy to deal with this in code, it must be said. You could keep track of when you enter and exit a L<Pod::Item> node, and inside your L<Pod::Block::Para> handling code, check to see if you're in a L<Pod::Item> node and suppress the C<< <p>..</p> >> appropriately.

Event-based systems would check to see when a C<enter-pod-item> and C<exit-pod-item> event fires, and keep track of it that way. This means, though, that you have to add bookkeeping code to every L<Pod> node type that might want to suppress a C<< <p>..</p> >> layer. And then code inside the L<Pod::Block::Para> handler that does just that, maybe even twice because you have to check once on the way in, once on the way out in an event-based system.

I think it's simpler to centralize the code in the L<Pod::Block::Para> handler, and check whether that paragraph is the child of an L<Pod::Item> node. The check can be done at that point and not need to be "scattered."

So this module makes certain that each node (except for the root) has a valid C<.parent> link, that way inside the L<Pod::Block::Para> handler you can check C<<$.parent !~~ Node::Item or $.html ~= '<p>'>>.

The other motivation is a bit more subtle, and focuses on the L<Pod::Table> class. It has both a C<.header> and C<.contents> attribute, and I'd rather have the <.contents> attribute B<always> contain the text associated with the object. So, rather than a single L<Node::Table> mimic with a C<.header>, the L<Node::Table> contains an optional L<Node::Table::Header> object and an equally-optional (ya never know, someone may write a POD table with headers, mean to fill in the content later, and never does) L<Node::Table::Body> object.

=head1 Layout

This is a bit spread-out, but it does make walking the tree of objects dead-simple. In fact, here's how you do it:

  sub walk-tree( $root ) {
    my $first-child = $root.first-child;

    say "<$root>";
    say $root.contents if $root.^can('contents');
    while $first-child {
      walk-tree( $first-child );
      $first-child = $first-child.next-sibling;
    }
    say "</$root>";
  } 

POD nodes either are leaf nodes - meaning that they have no internal structure, like a L<Node::Text> node, or branch nodes, meaning they have internal structures, like a L<Node::Document> node containing one or more other nodes.

You can use the C<.is-leaf> and C<.is-branch> methods to test for that, or just check the C<.first-child> attribute directly.

=head2 Migod, it's full of references.

Each node has:

=item .parent

  Its immediate parent node, or Nil if no parent.

=item .previous-sibling

  The node that occurs "before" it depth-first, or Nil if it's the first.

=item .next-sibling

  The node that follows it, or Nil if it's the end.

=item .first-child

  The first content node, or Nil if it has no contents.

=item .last-child

  The last content node, or Nil if it has no contents. Kind of pointless unless you want to iterate backwards through the tree, but it's there if you need it.

Simple tree-walking code is given above, in case you don't want to mess with the algorithm, and it even generates something like XML/HTML. The nodes correspond pretty much to how HTML would lay out, but you're welcome to interpret the nodes as you like.

=head1 METHODS

=item to-tree( $pod )

Given Perl 6 POD, return a different tree structure, along with some useful annotations.

=end pod

#
#                    parent
#                       ^
#                       |
# previous-sibling <- $node -> next-sibling
#                     |    \
#                     |     --------,
#                     V              \
#                    first-child -> last-child
#
my role Node::Visualization {
	method indent( Int $layer ) { ' ' xx $layer }

	method display( $layer ) {
		my @layer =
			self.WHAT.perl ~ "(\n",
			'  ' ~ self.parent ?? ':parent()' !! ':!parent',
			")\n";
		;
		return join( '', map { self.indent( $layer ) ~ $_ }, @layer );
	}

	method visualize( $layer = 0 ) {
		my $text = self.display( $layer );
		my $child = $.first-child;
		while $child {
			$text ~= $child.visualize( $layer + 1 );
			$child = $child.next-sibling;
		}
		$text;
	}
}
class Node {
	also does Node::Visualization;
	has $.parent is rw;
	has $.first-child is rw;
	has $.next-sibling is rw;
	has $.previous-sibling is rw;
	has $.last-child is rw;

	method replace-with( $node ) {
		$node.parent = $.parent;
		$node.previous-sibling = $.previous-sibling;
		$node.next-sibling = $.next-sibling;
		# Don't touch first- and last-child.

		if $.parent and $.parent.first-child === self {
			$.parent.first-child = $node;
		}
		if $.parent and $.parent.last-child === self {
			$.parent.last-child = $node;
		}
		if $.previous-sibling {
			$.previous-sibling.next-sibling = $node;
		}
		if $.next-sibling {
			$.next-sibling.previous-sibling = $node;
		}
	}

	method add-below( $to-insert ) {
		return unless $to-insert;
		$to-insert.parent = self;
		$to-insert.next-sibling = Nil;
		if $.first-child {
			$to-insert.previous-sibling = $.last-child;
			$.last-child.next-sibling = $to-insert;
			$.last-child = $to-insert;
		}
		else {
			$.first-child = $to-insert;
			$.last-child = $to-insert;
		}
	}
}

class Node::Bold is Node { }

class Node::Code is Node { }

class Node::Comment is Node { }

class Node::Document is Node { }

class Node::Entity is Node {
	has $.contents;
}

class Node::Item is Node { }

class Node::Link is Node {
	has $.url;
}

class Node::List is Node { }

class Node::Paragraph is Node { }

class Node::Section is Node {
	has $.title;
}

# XXX What is this?...
class Node::Reference is Node {
	has $.title;
}

class Node::Heading is Node {
	has $.level;
}

class Node::Text is Node {
	has $.value;
}

class Node::Table is Node { }

class Node::Table::Header is Node { }

class Node::Table::Data is Node { }

class Node::Table::Body is Node { }

class Node::Table::Body::Row is Node { }

my role Node-Helpers {
	method add-contents-below( $node, $pod ) {
		for @( $pod.contents ) -> $element {
			$node.add-below( self.to-node( $element ) );
		}
	}

	multi method to-node( $pod ) {
		die "Unknown Pod type " ~ $pod.gist;
	}

	multi method to-node( Pod::Block::Code $pod ) {
		my $node = Node::Code.new;
		self.add-contents-below( $node, $pod );
		$node;
	}

	multi method to-node( Pod::Block::Comment $pod ) {
		my $node = Node::Comment.new;
		self.add-contents-below( $node, $pod );
		$node;
	}

	multi method to-node( Pod::Block::Named $pod ) {
		given $pod.name {
			when 'pod' { self.new-Node-Document( $pod ) }
			default { self.new-Node-Section( $pod ) }
		}
	}

	multi method to-node( Pod::Block::Para $pod ) {
		my $node = Node::Paragraph.new;
		self.add-contents-below( $node, $pod );
		$node;
	}

	multi method to-node( Pod::Block::Table $pod ) {
		my $node = Node::Table.new;
		$node.add-below( self.new-Node-Table-Header( $pod ) )
			if $pod.headers.elems;
		$node.add-below( self.new-Node-Table-Body( $pod ) )
			if $pod.contents.elems;
		$node;
	}

	multi method to-node( Pod::FormattingCode $pod ) {
		given $pod.type {
			when 'B' {
				my $node = Node::Bold.new;
				self.add-contents-below( $node, $pod );
				$node;
			}
			when 'C' {
				my $node = Node::Code.new;
				self.add-contents-below( $node, $pod );
				$node;
			}
			when 'E' {
				my $node = Node::Entity.new(
					:contents( $pod.contents )
				);
				$node;
			}
			when 'L' {
				my $node = Node::Link.new(
					:url( $pod.meta )
				);
				self.add-contents-below( $node, $pod );
				$node;
			}
			when 'R' {
				my $node = Node::Reference.new;
				self.add-contents-below( $node, $pod );
				$node;
			}
			default { self.new-Node-Section( $pod ) }
		}
	}

	multi method to-node( Pod::Heading $pod ) {
		my $node = Node::Heading.new( :level( $pod.level ) );
		self.add-contents-below( $node, $pod );
		$node;
	}

	multi method to-node( Pod::Item $pod ) {
		my $node = Node::Item.new( :level( $pod.level ) );
		self.add-contents-below( $node, $pod );
		$node;
	}

	multi method to-node( Str $pod ) {
		my $node = Node::Text.new( :value( $pod ) );
		$node;
	}

	method new-Node-Table-Data( $pod ) {
		my $node = Node::Table::Data.new;
		$node.add-below( self.to-node( $pod ) );
		$node;
	}

	method new-Node-Table-Header( $pod ) {
		my $node = Node::Table::Header.new;
		for @( $pod.headers ) -> $element {
			$node.add-below( self.new-Node-Table-Data( $element ) );
		}
		$node;
	}

	method new-Node-Table-Body-Row( $pod ) {
		my $node = Node::Table::Body::Row.new;
		for @( $pod ) -> $element {
			$node.add-below( self.new-Node-Table-Data( $element ) );
		}
		$node;
	}

	method new-Node-Table-Body( $pod ) {
		my $node = Node::Table::Body.new;
		for @( $pod.contents ) -> $element {
			$node.add-below( 
				self.new-Node-Table-Body-Row( $element )
			);
		}
		$node;
	}

	method new-Node-Document( $pod ) {
		my $node = Node::Document.new;
		self.add-contents-below( $node, $pod );
		$node;
	}

	method new-Node-Section( $pod ) {
		my $node = Node::Section.new( :title( $pod.name ) );
		self.add-contents-below( $node, $pod );
		$node;
	}
}

class Pod::To::Tree {
	also does Node-Helpers;

	sub add-list( $tree ) {
		my $child = $tree.first-child;
		while $child {
			add-list( $child );
			if $child ~~ Node::Item {
				my $new-list = Node::List.new;
				$new-list.add-below( $child );
				$child.replace-with( $new-list );
			}
			$child = $child.next-sibling;
		}
	}

	sub fixup-root-item( $tree ) {
		if $tree ~~ Node::Item {
			my $new-list = Node::List.new;
			$new-list.add-below( $tree );
			return $new-list;
		}
		$tree;
	}

	method to-tree( $pod ) {
		my $tree = self.to-node( $pod );
		$tree = fixup-root-item( $tree );
		add-list( $tree );
		return $tree;
	}
}

# vim: ft=perl6