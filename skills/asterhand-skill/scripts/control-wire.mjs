// Compatibility exports. Encryption and frame validation are defined once in shared/.
import {wire} from './project-runtime.mjs';
export const {LIMIT,seal,open,invitation,parseInvitation,sealFrame,openFrame}=wire;
