# This module implements various templates for formValidate()

package VNDB::Util::ValidateTemplates;

use strict;
use warnings;


TUWF::set(
  validate_templates => {
    id    => { template => 'uint', max => 1<<40 },
    page  => { template => 'uint', max => 1000 },
  }
);

1;
