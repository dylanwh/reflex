package RunnerRole;
use Reflex::Role;

attribute_parameter stdin   => "stdin";
attribute_parameter stdout  => "stdin";
attribute_parameter stderr  => "stdin";
attribute_parameter pid     => "pid";

callback_parameter  cb_stdout_data    => qw( on stdout data );
callback_parameter  cb_stdout_error   => qw( on stdout error );

callback_parameter  cb_stdout_closed  => qw( on stdout closed );
event_parameter     ev_stdout_closed  => qw( _ stdout closed );

callback_parameter  cb_stderr_data    => qw( on stderr data );
callback_parameter  cb_stderr_error   => qw( on stderr error );

callback_parameter  cb_stderr_closed  => qw( on stderr closed );
event_parameter     ev_stderr_closed  => qw( _ stderr closed );

callback_parameter  cb_exit => qw( on pid exit );
event_parameter     ev_exit => qw( _ pid exit );

method_parameter    method_put => qw( put stdin _ );

role {
	my $p = shift;

	with 'Reflex::Role::OutStreaming' => {
		handle      => $p->stdin(),
		method_put  => $p->method_put(),
	};

	my $m_stdout_stop = "stop_" . $p->stdout();
	my $cb_stdout_closed = $p->cb_stdout_closed();
	my $ev_stdout_closed = $p->ev_stdout_closed();

	after $cb_stdout_closed => sub {
		my ($self, $args) = @_;
		$self->$m_stdout_stop();
	};

	with 'Reflex::Role::InStreaming' => {
		handle    => $p->stdout(),
		cb_data   => $p->cb_stdout_data(),
		cb_error  => $p->cb_stdout_error(),
		cb_closed => $cb_stdout_closed,
	};

	my $m_stderr_stop = "stop_" . $p->stderr();
	my $cb_stderr_closed = $p->cb_stderr_closed();
	my $ev_stderr_closed = $p->ev_stderr_closed();

	after $cb_stderr_closed => sub {
		my ($self, $args) = @_;
		$self->$m_stderr_stop();
		$self->emit(event => $ev_stderr_closed, args => $args);
	};

	with 'Reflex::Role::InStreaming' => {
		handle    => $p->stderr(),
		cb_data   => $p->cb_stderr_data(),
		cb_error  => $p->cb_stderr_error(),
		cb_closed => $cb_stderr_closed,
	};

	with 'Reflex::Role::PidCatcher' => {
		pid     => 'pid',
		cb_exit => $p->cb_exit(),
		ev_exit => $p->ev_exit(),
	};
};

1;

__END__

extends 'Reflex::Base';

use Reflex::Trait::Observed;
use Reflex::PID;

use Carp qw(croak);
use IPC::Run qw(start);
use Symbol qw(gensym);


__END__

observes process => ( isa => 'Maybe[Reflex::PID]', is => 'rw' );

has [qw(stdin stdout stderr)] => (
	isa => 'Maybe[FileHandle]',
	is  => 'rw',
);

has ipc_run => ( isa => 'IPC::Run', is => 'rw' );

has cmd => (
	isa       => 'ArrayRef',
	is        => 'ro',
	required  => 1,
);

### Reap the child process.

sub on_process_exit {
	my ($self, $args) = @_;
	$self->emit(event => 'exit', args  => $args);
}

sub kill {
	my ($self, $signal) = @_;
	croak "no process to kill" unless $self->process();
	$signal ||= 'TERM';
	kill $signal, $self->process()->pid();
}

### Write to standard input.

sub on_stdin_error {
	my ($self, $args) = @_;
	$self->emit(event => 'stdin_error', args => $args);
}

with 'Reflex::Role::Writing' => { handle  => 'stdin' };

sub on_stdin_writable {
	my ($self, $arg) = @_;
	my $octets_left = $self->flush_stdin();
	return if $octets_left;
	$self->flush_stdin();
}

with 'Reflex::Role::Writable' => { handle => 'stdin' };

### Read from standard output.

sub on_stdout_readable {
	my ($self, $arg) = @_;
	my $octets_read = $self->read_stdout($arg);
	warn $octets_read;
	return if $octets_read;
	if (defined $octets_read) {
		warn 111;
		$self->pause_stdout_readable();
		return;
	}
	$self->stop_stdout_readable();
}

sub on_stdout_error {
	my ($self, $args) = @_;
	$self->emit(event => 'stdout_error', args => $args);
	$self->stop_stdout_readable();
}

with 'Reflex::Role::Reading' => {
	handle      => 'stdout',
	cb_data     => 'on_stdout',
	ev_data     => 'stdout',
};

with 'Reflex::Role::Readable' => {
	handle      => 'stdout',
	cb_ready    => 'on_stdout_readable',
};

### Read from standard error.

sub on_stderr_error {
	my ($self, $args) = @_;
	$self->emit(event => 'stderr_error', args => $args);
	$self->stop_stderr_readable();
}

sub on_stderr_readable {
	my ($self, $arg) = @_;
	my $octets_read = $self->read_stderr($arg);
	warn $octets_read;
	return if $octets_read;
	if (defined $octets_read) {
		warn 111;
		$self->pause_stderr_readable();
		return;
	}
	$self->stop_stderr_readable();
}

with 'Reflex::Role::Reading' => {
	handle      => 'stderr',
	cb_data     => 'on_stderr',
	ev_data     => 'stderr',
};

with 'Reflex::Role::Readable' => {
	handle      => 'stderr',
	cb_ready    => 'on_stderr_readable',
};

sub BUILD {
	my $self = shift;

	my ($fh_in, $fh_out, $fh_err) = (gensym(), gensym(), gensym());

	$self->ipc_run(
		start(
			$self->cmd(),
			'<pipe', $fh_in,
			'>pipe', $fh_out,
			'2>pipe', $fh_err,
		)
	) or die "IPC::Run start() failed: $? ($!)";

	$self->process(
		Reflex::PID->new(
			pid => $self->ipc_run->{KIDS}[0]{PID}
		)
	);

	$self->stdin($fh_in);
	$self->stdout($fh_out);
	$self->stderr($fh_err);
}

1;
